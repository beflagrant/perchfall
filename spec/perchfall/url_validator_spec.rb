# frozen_string_literal: true

require "spec_helper"

RSpec.describe Perchfall::UrlValidator do
  subject(:validator) { described_class.new }

  describe "#validate!" do
    context "permitted schemes" do
      it "accepts http URLs" do
        expect { validator.validate!("http://example.com") }.not_to raise_error
      end

      it "accepts https URLs" do
        expect { validator.validate!("https://example.com/path?q=1") }.not_to raise_error
      end
    end

    context "forbidden schemes" do
      it "rejects file:// (local filesystem read)" do
        expect { validator.validate!("file:///etc/passwd") }
          .to raise_error(ArgumentError, /file/)
      end

      it "rejects ftp://" do
        expect { validator.validate!("ftp://example.com") }
          .to raise_error(ArgumentError, /ftp/)
      end

      it "rejects javascript:" do
        expect { validator.validate!("javascript:alert(1)") }
          .to raise_error(ArgumentError, /javascript/)
      end

      it "rejects data: URIs" do
        expect { validator.validate!("data:text/html,<h1>hi</h1>") }
          .to raise_error(ArgumentError, /data/)
      end

      it "rejects bare strings with no scheme" do
        expect { validator.validate!("example.com") }
          .to raise_error(ArgumentError)
      end
    end

    context "invalid URLs" do
      it "rejects strings that are not parseable URIs" do
        expect { validator.validate!("not a url at all \x00") }
          .to raise_error(ArgumentError, /Invalid URL/)
      end

      it "rejects empty string" do
        expect { validator.validate!("") }
          .to raise_error(ArgumentError)
      end
    end

    context "error message" do
      it "names the rejected scheme" do
        expect { validator.validate!("file:///etc/passwd") }
          .to raise_error(ArgumentError, /"file"/)
      end

      it "names the permitted schemes" do
        expect { validator.validate!("ftp://example.com") }
          .to raise_error(ArgumentError, /http, https/)
      end
    end
  end
end
