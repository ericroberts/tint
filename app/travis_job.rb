require "json"
require "pathname"
require "securerandom"

module Tint
	class TravisJob
		attr_reader :job_id, :site, :status

		def initialize(site_or_payload, job_id=SecureRandom.uuid, status=nil)
			if site_or_payload.is_a?(Tint::Site)
				@site = site_or_payload
			else
				@payload = site_or_payload
				@site = Tint::Site.new(DB[:sites][site_id: @payload['site']['site_id']])
			end

			@job_id = job_id
			@status = status
		end

		def self.get(job_id)
			queue = Pathname.new(ENV.fetch("TRAVIS_WORKER_BASE_DIR")).realpath
			{
				created: queue.join("10-created.d"),
				received: queue.join("30-received.d"),
				started: queue.join("50-started.d"),
				finished: queue.join("70-finished.d")
			}.each do |status, dir|
				if (path = dir.join("#{job_id}.json")).exist?
					if dir.join("#{job_id}.state").exist?
						status = dir.join("#{job_id}.state").open.read.strip.to_sym
					end

					return TravisJob.new(JSON.parse(path.open.read), job_id, status)
				end
			end
		end

		def log_path
			Pathname.new(ENV.fetch("TRAVIS_WORKER_BASE_DIR")).realpath.join("log").join("#{job_id}.log")
		end

		def enqueue!
			if status
				raise "This job is already in the queue."
			end

			@status = :created
			Pathname.new(ENV.fetch("TRAVIS_WORKER_BASE_DIR")).realpath.
			         join("10-created.d").join("#{job_id}.json").open('w') do |f|
				f.puts(JSON.dump(
					job: { id: job_id },
					site: site.to_h
				))
			end
		end
	end
end
