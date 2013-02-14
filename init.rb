#!/usr/bin/env ruby

require 'json'
require 'fileutils'
require 'digest/md5'

include FileUtils

# Parse config file
config = JSON.parse(IO.read('config.json'))

# Backup or Restore ?
if(ARGV.include?('-b') || ARGV.include?('--backup'))

	# Debug?
	debug = config['debug'] ? true : false

	# Check if the paths is empty
	raise "There's nothing to backup, the path is empty" if config['paths'].empty?

	# Check if there are missing paths in config
	error_paths = []
	config['paths'].each do |p|
		error_paths << p unless File.exists?(p['path'])
	end
	raise "There are missing paths, here's the list: #{error_paths.join(', ')}" if !error_paths.empty?

	# If the configs folder doesn't exists, create it
	if !File.directory?('configs')
		mkdir_p('configs')
		touch('configs/.gitkeep')
	end

	# Remove files from configs folder
	Dir.entries('configs').each do |p|
		rm_r('configs/' + p, :verbose => debug) unless p == '.' || p == '..' || p == '.git' || p == '.gitkeep'
	end

	# Copy paths to configs folder
	config['paths'].each_with_index do |p, i|
		hash = config['paths'][i]['hash'] = Digest::MD5.hexdigest(p['path'] + File.mtime(p['path']).to_s)
		cp_r(p['path'], "configs/#{hash}", :verbose => debug)
	end

	# Copy the config.json file so we can restore later
	File.open('configs/config.json', 'w'){|f| f.write(config.to_json)}

	# Git repository
	cd('configs')
	%x[git init] if !File.exists?('.git')
	%x[git add -A .]
	commit_message = config['git']['commit_message'].to_s.empty? ? "Commited @ #{Time.new().strftime('%Y-%m-%d %H:%M:%S')}" : config['git']['commit_message']
	%x[git commit -m "#{commit_message}"]
	origin_exists = %x[git remote -v | grep origin]
	%x[git remote add origin #{config['git']['url']}] unless !origin_exists.empty?
	%x[git remote set-url origin #{config['git']['url']}] unless origin_exists.empty?
	%x[git push origin master] unless (ARGV.include?('-np') || ARGV.include?('--no-push'))

elsif(ARGV.include?('-r') || ARGV.include?('--restore'))

	raise "There's no Git URL defined" if(ARGV.last == '-r' || ARGV.last == '--restore')

	# remove configs folder if exists
	rm_r('configs') if File.exists?('configs')

	# git pull remote
	%x[git clone #{ARGV.last} configs]

	# load the new config file
	config = JSON.parse(File.read('configs/config.json'))

	config['paths'].each_with_index do |p, i|
		hash = config['paths'][i]['hash']
		cp_r("configs/#{hash}", p['path'], :verbose => debug)
	end

elsif(ARGV.include?('-h') || ARGV.include?('--help'))
	puts File.read('README.md')
else
	raise 'Choose one of this options: --backup or --restore'
end