#!/usr/bin/env ruby
# frozen_string_literal: true

# gPhoto-uploader: Goolge Photos uploader using Google Photos API
# usage: ./gPhoto-uploader.rb [OPTION] <photos_dir>
#
# author:    miyake13000<https://github.com/miyake13000>
# copylight: 2022 miyake13000
# license:   MIT license

VERSION = '0.1.0'
GOOGLE_TOKEN_PATH = './credentials/tokens.json'

IMAGE_EXPANTIONS = ['.png', '.jpg']

require 'optparse'
require 'json'
require 'uri'
require 'net/http'

def main(argv)
  begin
    params = get_cmdline_params(argv)
  rescue OptionParser::InvalidOption
    puts 'gPhoto-uploader: Invalid argumet'
    exit 1
  rescue => e
    puts e.message
    exit 1
  end

  photos_dir = params[:path]
  photos = Photo.get_from(photos_dir)
  if photos.length.zero?
    puts 'No photo was found'
    exit 0
  end

  gphoto_uploader = GooglePhotosUploader.new(Token.new(GOOGLE_TOKEN_PATH))

  photos.each do |photo|
    puts "Uploading #{photo.path}..."
    url = gphoto_uploader.upload(photo)
    puts "Complete to upload (#{url})"
  rescue => e
    puts "Failed to upload photo: #{photo.path}"
    puts e.message
    exit 1
  end
end

def get_cmdline_params(argv)
  params = {}
  OptionParser.new do |opt|
    opt.on('-r', '--remove', 'Remove uploaded photos') { |bool| option[:remove_flag] = bool }
    opt.on('-y', '--yes', 'Answer \'yes\' to all choises automatically') { |bool| option[:yes_flag] = bool }
    opt.order!(argv)

    if argv.empty?
      puts 'gPhoto-uploader: Missing photos dir'
      exit 1
    end

    params[:path] = argv[0]
  end
  params
end

class Photo
  attr_reader :path

  def initialize(path)
    @path = path
  end

  def self.get_from(dir_path)
    photos = []
    Dir.foreach(dir_path) do |file_name|
      path = File.join(dir_path, file_name)
      if file_name == '.' || file_name == '..'
        next
      elsif File.directory?(path)
        photos += get_from(path)
      elsif photo?(path)
        photos.push(Photo.new(path))
      end
    end
    photos
  end

  def name
    File.basename(@path)
  end

  def content
    File.open(@path).read
  end

  def self.photo?(file)
    IMAGE_EXPANTIONS.include?(File.extname(file))
  end
end

class Token
  # Read some values form google_token_path and refresh token
  def initialize(google_token_path)
    # read some values from google_token_path
    token = JSON.parse(File.open(google_token_path).read)
    @refresh_token = token['refresh_token']
    @client_id = token['client_id']
    @client_secret = token['client_secret']
    @expiration_time = token['expires_in']

    # update token
    @access_tokoen = update_token
    @last_updated_time = Time.now
  end

  # return access token
  def access_token
    # if current access_token expires, update token
    if expired?
      update_token
      @last_updated_time = Time.now
    end

    @access_token
  end

  private

  # Check whether current access token is expires
  def expired?
    passed_time = Time.now - @last_updated_time
    passed_time > @expiration_time.to_f
  end

  # update token
  def update_token
    request = { refresh_token: @refresh_token,
                client_id: @client_id,
                client_secret: @client_secret,
                grant_type: 'refresh_token' }
    header = { 'Content-Type' => 'application/json' }
    uri = URI.parse('https://www.googleapis.com/oauth2/v4/token')

    res = Net::HTTP.start(uri.host, uri.port, use_ssl: true) do |http|
      http.verify_mode = OpenSSL::SSL::VERIFY_NONE
      http.post(uri.request_uri, request.to_json, header)
    end

    new_access_token = JSON.parse(res.body)['access_token']
    @access_token = new_access_token
  end
end

class GooglePhotosUploader
  def initialize(token)
    @token = token
  end

  def upload(photo)
    @upload_url = 'https://photoslibrary.googleapis.com/v1/uploads'
    @mkmedia_url = 'https://photoslibrary.googleapis.com/v1/mediaItems:batchCreate'

    media_item_id = upload_photo(photo, @upload_url, @token)
    create_media_item(@mkmedia_url, @token, media_item_id)
  rescue => e
    raise e.message
  end

  private

  def upload_photo(photo, url, token)
    header = {
      'Authorization' => "Bearer #{token.access_token}",
      'Content-Type' => 'application/octet-stream',
      'X-Goog-Upload-Protocol' => 'raw',
      'X-Goog-Upload-File-Name' => photo.name
    }
    uri = URI.parse(url)

    res = Net::HTTP.start(uri.host, uri.port, use_ssl: true) do |http|
      http.verify_mode = OpenSSL::SSL::VERIFY_NONE
      http.post(uri.request_uri, photo.content, header)
    end

    if res.code == '200'
      res.body
    else
      raise "response is not ok (200)\n#{res.body}"
    end
  end

  def create_media_item(url, token, media_item_id)
    header = {
      'Authorization' => "Bearer #{token.access_token}",
      'Content-Type' => 'application/json'
    }
    req = { newMediaItems: { simpleMediaItem: { uploadToken: media_item_id } } }
    uri = URI.parse(url)

    res = Net::HTTP.start(uri.host, uri.port, use_ssl: true) do |http|
      http.verify_mode = OpenSSL::SSL::VERIFY_NONE
      http.post(uri.request_uri, req.to_json, header)
    end

    if res.code != '200'
      raise "response is not success (200)\n#{res.body}"
    end

    res_json = JSON.parse(res.body)['newMediaItemResults'][0]
    if res_json['status']['message'] == 'Success'
      res_json['mediaItem']['productUrl']
    else
      raise "response is not success\n#{res.body}"
    end
  end
end

main(ARGV)
