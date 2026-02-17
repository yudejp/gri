require 'rack/request'
require 'gri/gparams'

module GRI
  class Request < Rack::Request
    MAX_QUERY_STRING_SIZE = 8192
    MAX_PARAM_COUNT = 200
    MAX_KEY_SIZE = 128
    MAX_VALUE_SIZE = 2048

    def query_string=(s)
      @query_string = s
      @gparams = @params = nil
    end

    alias query_string0 query_string
    def query_string
      @query_string || query_string0
    end

    def gparams
      @gparams ||= gparse_query query_string
    end

    def gparse_query qs
      params = GParams.new
      qstr = (qs || '').to_s
      qstr = qstr.byteslice(0, MAX_QUERY_STRING_SIZE) if qstr.bytesize > MAX_QUERY_STRING_SIZE
      qstr.split(/[&;] */n, MAX_PARAM_COUNT + 1).first(MAX_PARAM_COUNT).each {|item|
        k, v = item.split('=', 2).map {|s| Rack::Utils.unescape s.to_s}
        next if k.nil? or k.empty?
        next if k.bytesize > MAX_KEY_SIZE
        v = v.to_s
        v = v.byteslice(0, MAX_VALUE_SIZE) if v.bytesize > MAX_VALUE_SIZE
        params[k] = v
      }
      params
    end
  end
end
