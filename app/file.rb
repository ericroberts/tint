require "filemagic"
require "yaml"

require_relative "resource"
require_relative "directory"

module Tint
	class File < Resource
		def text?
			mime.split("/").first == "text"
		end

		def image?
			mime.split("/").first == "image"
		end

		def mime
			FileMagic.open(:mime) { |magic| magic.file(path.to_s) }
		end

		def markdown?
			[".md", ".markdown"].include? extension
		end

		def yml?
			[".yaml", ".yml"].include? extension
		end

		def stream(force_binary=false)
			if !force_binary && text?
				path.each_line.with_index do |line, idx|
					yield line.chomp, idx
				end
			else
				f = path.open
				idx = 0
				until f.eof?
					yield f.read(4096), idx
					idx += 1
				end
			end
		end

		def stream_content
			has_frontmatter = false
			doc_start = 0
			stream do |line, idx|
				if doc_start < 2
					has_frontmatter = true if line == '---' && idx == 0
					doc_start += 1 if line == '---'
					next if has_frontmatter
				end

				yield line
			end
		end

		def content?
			detect_content_or_frontmatter[0]
		end

		def frontmatter?
			detect_content_or_frontmatter[1]
		end

		def frontmatter
			from_filename = filename_frontmatter_candidates.reduce({}) do |data, pieces|
				catch(:done) do
					new_data, final_path = pieces.reduce([data, path.basename.to_s]) do |(acc, path), piece|
						if (result = piece_match(piece, path))
							[piece["key"] ? acc.merge(piece["key"] => result[:data]) : acc, result[:path]]
						else
							throw(:done, data) # Did not match
						end
					end

					throw(:done, data) unless final_path == "" || final_path[0] == "." # Must consume whole filename

					new_data
				end
			end

			# From frontmatter takes precedence
			from_front = YAML.safe_load(open(path), [Date, Time]) || {} rescue {}
			from_filename.merge(from_front)
		end

		def to_h(_=nil)
			super.merge(mime: mime)
		end

		def log
			site.git.log.path(relative_path)
		end

	protected

		def extension
			@extension ||= path.extname
		end

		def detect_content_or_frontmatter
			@content_or_frontmatter ||= begin
				has_frontmatter = false
				path.each_line.with_index do |line, idx|
					line.chomp!
					if line == '---' && idx == 0
						has_frontmatter = true
						next
					end

					if has_frontmatter && line == '---'
						return [true, has_frontmatter]
					end
				end

				[!has_frontmatter, has_frontmatter]
			end
		end

		def filename_frontmatter_candidates
			@filename_frontmatter_candidates ||=
				(site.config["filename_frontmatter"] || {}).map do |(glob, pieces)|
					matches = Pathname.glob([parent.path.join(glob), site.cache_path.join(glob)])
					matches.include?(path) ? pieces : nil
				end.compact
		end

		def piece_match(piece, path)
			if piece.has_key?("match") && (match = /^#{piece["match"]}/.match(path))
				{ data: match.to_s, path: match.post_match }
			elsif piece.has_key?("strptime")
				begin
					time = if Input.type(piece["key"], nil, site) == Input::Date
						Date.strptime(path, piece["strptime"])
					else
						Time.strptime(path, piece["strptime"])
					end
					{ data: time, path: path.sub(time.strftime(piece["strptime"]), "") }
				rescue ArgumentError
					# Parse failed, so return nil
				end
			end
		end
	end
end
