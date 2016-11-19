require File.expand_path '../spec_helper', __FILE__

RSpec.describe Reel::H2::Server::HTTP do

  it "sends HTTP/2 response headers and body" do
    ex = nil

    handler = proc do
      respond :ok, {'test-header' => 'test_value'}, 'test_body'
      goaway
    end

    with_h2(handler) do
      c = H2::Client.get
      expect(c.streams[:get]['/'].length).to eq(1)
      s = c.streams[:get]['/'][0]
      expect(s.headers[':status']).to eq('200')
      expect(s.headers['content-length']).to eq('test_body'.bytesize.to_s)
      expect(s.headers['test-header']).to eq('test_value')
      expect(s.body).to eq('test_body')
    end

    raise ex if ex
  end

  it "reads HTTP/2 request headers" do
    ex = nil

    handler = proc do
      begin
        expect(request_headers['test-header']).to eq('test_value')
      rescue RSpec::Expectations::ExpectationNotMetError => ex
      ensure
        respond :ok
        goaway
      end
    end

    with_h2(handler) do
      c = H2::Client.get headers: {'test-header' => 'test_value'}
    end

    raise ex if ex
  end

  it "reads HTTP/2 request bodies" do
    ex = nil

    handler = proc do
      begin
        expect(request_body).to eq('test_body')
      rescue RSpec::Expectations::ExpectationNotMetError => ex
      ensure
        respond :ok
        goaway
      end
    end

    with_h2(handler) do
      c = H2::Client.get body: 'test_body'
    end

    raise ex if ex
  end

end

