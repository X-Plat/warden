# coding: UTF-8

require "warden/container/spawn"
require "warden/errors"
require "warden/util"

module Warden

  module Container

    module Features

      module CpuLimit

	include Spawn

        def limit_cpu(limit_cpu)
            ["cpu.shares"].each do |path|
              File.open(File.join(cgroup_path(:cpu), path), 'w') do |f|
                f.write(limit_cpu.to_s)
            end
          end
        end

        private :limit_cpu

        def do_limit_cpu(request, response)
          if request.cpu_limit
            begin
              limit_cpu(request.cpu_limit)
            rescue => e
              raise WardenError.new("Failed setting cpu limit: #{e}")
            else
              @resources["cpu_limit"] = request.cpu_limit
            end
          end

          cpu_limit = File.read(File.join(cgroup_path(:cpu), "cpu.shares"))
          response.cpu_limit = cpu_limit.to_i

          nil
        end
      end
    end
  end
end
