require 'fileutils'
require 'gri/updater'

module GRI
  class API
    NUMBER_RE = /\A-?\d+(?:\.\d+)?\z/

    def call env
      if env['PATH_INFO'] =~ %r{^/api/(\w+)/(\w+)/(\w+)\b}
        service_name, section_name, graph_name = $1, $2, $3
        req = Rack::Request.new env
        num_raw = req['number'].to_s.strip
        return [400, {}, ["NG\n"]] unless valid_number?(num_raw)
        num = parse_number num_raw
        root_dir = Config['root-dir'] || Config::ROOT_PATH
        cast_dir = root_dir + '/cast'
        service_dir = "#{cast_dir}/#{service_name}"
        host = section_name
        key = "num_#{graph_name}"
        FileUtils.mkdir_p service_dir

        records = [{'_host'=>host, '_key'=>key, 'num'=>num}]
        writer = Writer.create 'rrd', :gra_dir=>service_dir, :interval=>60
        writer.write records
        writer.finalize
        res = "OK\n"
      else
        res = "NG\n"
      end
      [200, {}, [res]]
    end

    def valid_number? s
      return false if s.empty? || s.size > 64
      s =~ NUMBER_RE
    end

    def parse_number s
      s.include?('.') ? s.to_f : s.to_i
    end
  end
end
