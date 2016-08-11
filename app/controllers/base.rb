module Tint
	module Controllers
		class Base < Sinatra::Base
			use OmniAuth::Builder do
				if ENV['GITHUB_KEY']
					provider :github, ENV['GITHUB_KEY'], ENV['GITHUB_SECRET'], scope: "user,repo"
				end

				if ENV['APP_URL']
					provider :indieauth, client_id: ENV['APP_URL']
				end
			end

			register Sinatra::Pundit
			register Sinatra::Namespace
			helpers Sinatra::Streaming, Tint::Helpers::Rendering

			set :views, ::File.expand_path('../../views', __FILE__)

			configure :development do
				set :show_exceptions, :after_handler
				register Sinatra::Reloader
			end

			configure do
				error Pundit::NotAuthorizedError do
					redirect to("/auth/login")
				end
			end

			enable :sessions
			set :session_secret, ENV["SESSION_SECRET"]
			set :sprockets, Sprockets::Environment.new
			set :method_override, true

			sprockets.append_path "assets/stylesheets"
			sprockets.css_compressor = :scss

			current_user do
				if ENV['SITE_PATH']
					{ user_id: 1 }
				else
					DB[:users][user_id: session['user'].to_i] if session['user']
				end
			end

			before do
				blank_is_nil!(params)
			end

			after do
				verify_authorized
			end

			get "/assets/*" do
				skip_authorization
				env["PATH_INFO"].sub!("/assets", "")
				settings.sprockets.call(env)
			end

		protected

			def site
				if ENV['SITE_PATH']
					Tint::Site.new(
						site_id: (params['site'] || 1).to_i,
						user_id: 1,
						cache_path: Pathname.new(ENV['SITE_PATH']).realpath,
						cloned: true,
						fn: "Local Site"
					)
				else
					Tint::Site.new(DB[:sites][site_id: params['site'].to_i])
				end
			end

			def blank_is_nil!(hash)
				hash.each do |k, v|
					case v
					when Hash
						blank_is_nil!(v)
					when Array
						hash[k] = v.map { |x| x.to_s == "" ? nil : x }
					else
						hash[k] = nil if v.to_s == ""
					end
				end
			end
		end
	end
end
