require 'rho/rhocontroller'

class SpecController < Rho::RhoController

  def run_all_tests
    run_spec('AsyncHttp')
    run_spec('Json')
    run_spec('Xml')
  end
  
end