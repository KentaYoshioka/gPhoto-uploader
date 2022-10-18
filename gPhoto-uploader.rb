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

require 'optparse'
require 'json'
require 'uri'
require 'net/http'

def main(argv)
  params = get_cmdline_params(argv)

  photos_dir = params[:path]
  photos = Photo.get_from(photos_dir)

  gphoto_uploader = GooglePhotosUploader.new(Token.new(GOOGLE_TOKEN_PATH))
  photos.each do |photo|
    gphoto_uploader.upload(photo)
  # rescue
  #   puts "Failed to upload photo: #{photo.name}"
  #   exit 1
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

  rescue OptionParser::InvalidOption
    puts 'gPhoto-uploader: Invalid argumet'
    exit 1
  end

  params
end

class Photo
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
    filename_with_extension = File.basename(@path)
    res = filename_with_extension.match(/(.+).(.+)$/)
    if res[0].nil?
      file_name = "temporary_#{rand}"
    else
      file_name = res[1]
    end
    file_name
  end

  def content
    File.open(@path).read
  end

  private

  def self.photo?(file)
    ['.jpg', '.png'].include?(File.extname(file))
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
    @access_tokoen = update_token()
    @last_updated_time = Time.now
  end

  # return access token
  def access_token
    # if current access_token expires, update token
    if expired?
      update_token()
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
    uri = URI.parse('https://www.googleapis.com/oauth2/v4/token')

    res = Net::HTTP.start(uri.host, uri.port, use_ssl: true) do |http|
      http.verify_mode = OpenSSL::SSL::VERIFY_NONE
      http.post(uri.request_uri, request.to_json, { 'Content-Type' => 'application/json' })
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
    # 画像データをアップロード
    @upload_url = 'https://photoslibrary.googleapis.com/v1/uploads'
    @mkmedia_url = 'https://photoslibrary.googleapis.com/v1/mediaItems:batchCreate'

    header = {
      'Authorization' => "Bearer #{@token.access_token}",
      'Content-Type' => 'application/octet-stream',
      'X-Goog-Upload-Protocol' => 'raw',
      'X-Goog-Upload-File-Name' => photo.name
    }

    uri = URI.parse(@upload_url)
    res = Net::HTTP.start(uri.host, uri.port, use_ssl: true) do |http|
      http.verify_mode = OpenSSL::SSL::VERIFY_NONE
      http.post(uri.request_uri, photo.content, header)
    end
    upload_token = res.body

    # メディアアイテムの作成
    header = {
      'Authorization' => "Bearer #{@access_token}",
      'Content-Type' => 'application/json'
    }
    req = { newMediaItems: { simpleMediaItem: { uploadToken: upload_token } } }
    uri = URI.parse(@mkmedia_url)
    res = Net::HTTP.start(uri.host, uri.port, use_ssl: true) do |http|
      http.verify_mode = OpenSSL::SSL::VERIFY_NONE
      http.post(uri.request_uri, req.to_json, header)
    end

    if res.code != 200
      puts "Failed to upload photo"
      puts "\n\n"
      puts res.body
      puts "\n\n"
      raise RuntimeError
    end

    result = JSON.parse(res.body)['newMediaItemResults'][0]

    if result['status']['message'] == 'OK'
      url = result['mediaItem']['productUrl']
      filename = result['mediaItem']['filename']
      "<#{url}|#{filename}>"
    else
      raise RuntimeError
    end
  end
end

main(ARGV)

