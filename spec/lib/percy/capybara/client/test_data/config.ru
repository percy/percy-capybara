require 'rack'

use Rack::Static, 
  :urls => {
    "/" => 'test-iframe.html',
    '/iframe/' => './iframe.html',
    '/iframe.html' => './iframe.html',
  }

run lambda { |env|
  [
    404,
    { 'Content-Type'  => 'text/html' },
    ['404 - page not found']
  ]
}
