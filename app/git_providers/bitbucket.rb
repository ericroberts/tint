require "json"
require "httparty"

module Tint
	module GitProviders
		class Bitbucket
			include HTTParty

			base_uri "https://api.bitbucket.org"

			def initialize(payload)
				@omniauth = JSON.parse(payload)
			end

			def repositories(exclude: [])
				get_repositories.reject { |repo|
					repo["scm"] != "git" || Array(exclude).include?(remote(repo))
				}.map { |repo|
					{
						fn: repo["name"],
						remote: remote(repo),
						link: repo["links"]["html"],
						description: repo["description"]
					}
				}
			end

			def add_deploy_key(remote)
				user, repo = extract_from_remote(remote)
				self.class.post(
					"/1.0/repositories/#{user}/#{repo}/deploy-keys",
					body: {
						accountname: user,
						repo_slug: repo,
						label: "Tint",
						key: ENV.fetch("SSH_PUBLIC")
					},
					headers: headers
				)
			end

			def subscribe(remote, callback)
				user, repo = extract_from_remote(remote)
				self.class.post(
					"/2.0/repositories/#{user}/#{repo}/hooks",
					body: {
						description: "Tint",
						url: callback,
						active: true,
						events: ["repo:push"]
					}.to_json,
					headers: headers.merge("Content-Type" => "application/json")
				)
			end

		protected

			attr_reader :omniauth

			def headers
				{ "Authorization" => "Bearer #{omniauth["credentials"]["token"]}" }
			end

			def remote(repo)
				repo["links"]["clone"].find { |link| link["name"] == "ssh" }["href"]
			end

			def get_repositories(repos=[], path="/2.0/repositories/#{omniauth["uid"]}?pagelen=100")
				response = self.class.get(path, headers: headers)

				repos = repos + Array(response["values"])
				if response["next"]
					get_repositories(repos, response["next"])
				else
					repos
				end
			end

			def extract_from_remote(remote)
				match_data = remote.match(/bitbucket\.org\/([^\/]+)\/(.+)\.git$/)
				[match_data[1], match_data[2]]
			end
		end
	end
end
