require "pathname"

module Tint
	class Resource
		extend Forwardable

		attr_reader :relative_path

		def_delegators :site, :user_id

		def initialize(site, relative_path)
			@site = site
			@relative_path = Pathname.new(relative_path).cleanpath
		end

		def parent
			@parent ||= Tint::Directory.new(site, relative_path.dirname)
		end

		def route
			site.route("files/#{relative_path}")
		end

		def path
			@path ||= begin
				path = site.cache_path.join(relative_path).realdirpath

				unless path.to_s.start_with?(site.cache_path.to_s)
					raise "File is outside of project scope!"
				end

				path
			end
		end

		def ==(other)
			other.is_a?(Resource) && other.path == path
		end

		def respond_to?(method)
			super || path.respond_to?(method)
		end

		def method_missing(method, *arguments, &block)
			path.public_send(method, *arguments, &block)
		end

	protected

		attr_reader :site
	end
end
