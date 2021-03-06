require "erb"
require "fileutils"
require "git"
require "git-annex"
require "shellwords"
require "tmpdir"

require_relative "resource"
require_relative "file"
require_relative "directory"
require_relative "path_helpers"

module Tint
	class Site
		module Config
			class Basenames < String
				yaml_tag "!basenames"

				def encode_with(coder)
					coder.represent_scalar("basenames", self)
				end

				def init_with(coder)
					self << coder.scalar
				end
			end
		end

		def initialize(options)
			@options = options
		end

		def ==(other)
			other.is_a?(Tint::Site) && cache_path == other.cache_path
		end

		def to_h
			@options.dup
		end

		def route(sub='')
			path = sub.split("/", -1).map { |s| ERB::Util.url_encode(s) }.join("/")
			"/#{@options[:site_id]}/#{path}"
		end

		def fn
			@options[:fn]
		end

		def domain
			@options[:domain]
		end

		def subdomain
			if domain && domain =~ /\.#{Regexp.escape(DOMAIN)}$/
				domain.sub(/\.#{Regexp.escape(DOMAIN)}$/, '')
			end
		end

		def users
			@options[:users]
		end

		def cache_path
			@cache_path ||= ensure_path(:cache_path)
		end

		def deploy_path
			@deploy_path ||= ensure_path(:deploy_path, @options[:domain])
		end

		def ssh_private_key_path
			priv = ssh_keys_path.join(@options[:site_id].to_s)

			unless priv.exist?
				system("ssh-keygen -q -t ed25519 -N '' -f #{Shellwords.escape(priv.to_s)}")
			end

			priv.chmod(0600)
			priv
		end

		def ssh_public_key_path
			pub = ssh_private_key_path.sub_ext(".pub")
			pub.chmod(0600)
			pub
		end

		def valid_config?
			begin
				unsafe_config
				true
			rescue
				false
			end
		end

		def unsafe_config
			config_file.exist? ? YAML.safe_load(config_file.open, [Date, Time, Config::Basenames]) : {}
		end

		def config
			@config ||= unsafe_config rescue {}
		end

		def show_config_warning?
			@options[:show_config_warning]
		end

		def config_file
			cache_path.join(".tint.yml")
		end

		def collections
			@collections ||= find_collections
		end

		def resource(path)
			resource = Tint::Resource.new(self, path)
			klass = if resource.directory? || (!resource.in_annex? && !resource.exist?)
				Tint::Directory
			elsif resource.file? || resource.in_annex?
				Tint::File
			else
				raise "This path is not a file or directory."
			end

			klass.new(self, path)
		end

		def git
			@git ||= Git.open(
				cache_path,
				env: { "SITE_PRIVATE_KEY_PATH" => ssh_private_key_path.to_s }
			)
		end

		def git?
			cache_path.join('.git').directory?
		end

		def log
			git.log.tap(&:size)
		rescue Git::GitExecuteError
			[] # No log
		end

		def status
			status = @options[:status] || if Tint.db
				job = Tint.db[:jobs].where(site_id: @options[:site_id]).order(:created_at).last
				job && "build_#{BuildJob.get(job[:job_id]).status}".to_sym
			end

			status && status.to_sym
		end

		def remote
			@options[:remote]
		end

		def build
			job = BuildJob.new(self)
			job.enqueue!

			Tint.db[:jobs].insert(job_id: job.job_id, site_id: @options[:site_id], created_at: Time.now) if Tint.db

			job
		end

		def clone(remote=@options[:remote])
			begin
				# First, do a shallow clone so that we are up and running
				# No single branch so that further operations can at least see remote branches
				Git.clone(
					remote,
					cache_path.basename,
					path: cache_path.dirname,
					depth: 1,
					no_single_branch: true,
					env: { "SITE_PRIVATE_KEY_PATH" => ssh_private_key_path.to_s }
				)

				# Make sure the UI can tell we are ready to rock
				open(cache_path.join('.git').join('tint-cloned'), 'w').close
			rescue
				Tint.db[:sites].where(site_id: @options[:site_id]).update(status: "clone_failed")

				# Something went wrong.  Nuke the cache
				clear_cache!
				return
			end

			Tint.db[:sites].where(site_id: @options[:site_id]).update(status: nil)

			begin
				# Fetch any large files from git-annex
				git.annex.get if git.annex?

				# Now, fetch the history for future use
				git.fetch(remote, unshallow: true)
			rescue
				# Something went wrong, keep the shallow copy that at least works
			end
		end

		def clear_cache!
			cache_path.rmtree
		end

		def cloned?
			@options[:cloned] || cache_path.join('.git').join('tint-cloned').exist?
		end

		def sync(remote=@options[:remote])
			if git? && cloned?
				git.fetch(remote, refs: "+refs/heads/*:refs/remotes/origin/*")
				git.reset_hard("remotes/origin/HEAD")

				# Fetch any large files from git-annex
				git.annex.get if git.annex?
			elsif !git?
				clone(remote)
			end
		end

		def commit_with(message, user=nil, tries: 1, depth: 1, &block)
			Dir.mktmpdir("tint-push") do |dir|
				begin
					git = Git.clone(
						@options[:remote],
						"clone",
						path: dir,
						depth: depth,
						no_single_branch: true,
						env: { "SITE_PRIVATE_KEY_PATH" => ssh_private_key_path.to_s }
					)

					path = Pathname.new(dir).join("clone")
					block.call(path, git)
					git.add(all: true)

					if maybe_commit(git, message, user)
						if ENV["SITE_PATH"]
							# If we push to a checked-out repository, we'll get nasty errors
							sync(path.to_s)
						else
							git.push
							git.annex.copy(to: "origin") if git.annex?
							sync
						end
					end

				rescue Git::GitExecuteError
					raise if tries > 4
					commit_with(message, user, tries: tries+1, depth: depth, &block)
				ensure
					# Make everything writeable so that mktmpdir cleanup will work
					FileUtils.chmod_R(0700, git.repo.to_s)
				end
			end
		end

		def makefile?
			cache_path.join("Makefile").exist?
		end

	protected

		def maybe_commit(git, message, user)
			begin
				status = git.status
			rescue Git::GitExecuteError
				commit(git, message, user)
				return true
			end

			status.each do |f|
				if f.type
					commit(git, message, user)
					return true
				end
			end

			false
		end

		def commit(git, message, user)
			if user && user.email
				git.commit("#{message} via tint", author: "#{user.fn} <#{user.email}>")
			else
				git.commit("#{message} via tint")
			end
		end

		def ssh_keys_path
			PathHelpers.ensure(Pathname.new(ENV.fetch("SSH_KEYS_PATH")))
		end

		def ensure_path(key, suffix=nil, env=key.to_s.upcase)
			PathHelpers.ensure(
				@options[key] || Pathname.new(ENV.fetch(env)).join(suffix || @options[:site_id].to_s)
			)
		end

		def find_collections(rooted_at = resource('.'))
			return [] unless rooted_at.is_a?(Tint::Directory)
			return [rooted_at] unless rooted_at.templates.empty?
			rooted_at.children(false).flat_map(&method(:find_collections))
		end
	end
end
