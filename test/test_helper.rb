ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require "minitest/mock"

class ActiveSupport::TestCase
  parallelize(workers: :number_of_processors) unless Gem.win_platform?
end
