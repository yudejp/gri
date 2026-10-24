require File.expand_path(File.dirname(__FILE__) + '/unittest_helper')

require 'gri/log'
require 'tmpdir'

module GRI

class TestLog < Test::Unit::TestCase
  def test_log
    time = Time.local(2014,1,2,3,4,56)
    formatter = Log::Formatter.new
    s = formatter.call nil, time, nil, 'test message'
    ae "2014-01-02 03:04:56 test message\n", s
  end

  def test_log_rotation_uses_configured_size
    previous_logger = Log.logger
    Dir.mktmpdir('gri-log') do |dir|
      path = File.join(dir, 'gri.log')
      Log.init path, :log_shift_age=>2, :log_shift_size=>200,
        :no_dash=>true
      20.times {Log.info 'collection event ' + ('x' * 40)}
      assert File.exist?(path + '.0'), 'log file was not rotated'
    end
  ensure
    Log.logger.close if Log.logger && Log.logger != previous_logger
    Log.logger = previous_logger
  end
end

end
