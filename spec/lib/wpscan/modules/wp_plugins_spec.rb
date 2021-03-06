shared_examples_for "WpPlugins" do

  before :all do
    @fixtures_dir      = SPEC_FIXTURES_WPSCAN_MODULES_DIR + '/wp_plugins'
    @plugins_file      = @fixtures_dir + "/plugins.txt"
    @plugin_vulns_file = @fixtures_dir + "/plugin_vulns.xml"
  end

  before :each do
    @wp_url = "http://example.localhost"
    @module = WpScanModuleSpec.new(@wp_url)
    @module.error_404_hash = Digest::MD5.hexdigest("Error 404!")
    @module.extend(WpPlugins)
  end

  describe "#plugins_from_passive_detection" do
    let(:passive_detection_fixtures) { @fixtures_dir + '/passive_detection' }

    it "should return an empty array" do
      stub_request_to_fixture(:url => @module.url, :fixture => File.new(passive_detection_fixtures + '/no_plugins.htm'))

      plugins = @module.plugins_from_passive_detection
      plugins.should be_empty
    end

    it "should return the expected plugins" do
      stub_request_to_fixture(:url => @module.url, :fixture => File.new(passive_detection_fixtures + '/various_plugins.htm'))

      expected_plugin_names = [
        'wp-minify',
        'comment-info-tip',
        'tweet-blender',
        'optinpop',
        's2member',
        'wp-polls',
        'commentluv'
      ]
      expected_plugins = []
      expected_plugin_names.each do |plugin_name|
        expected_plugins << WpPlugin.new(
          WpPlugin.create_location_url_from_name(plugin_name, @module.url),
          :name => plugin_name
        )
      end

      plugins = @module.plugins_from_passive_detection
      plugins.should_not be_empty
      plugins.sort.should === expected_plugins.sort
    end
  end

  describe "#plugins_targets_url" do
    let(:expected_for_only_vulnerable) {
      [WpPlugin.create_location_url_from_name("media-library", @module.url), WpPlugin.create_location_url_from_name("deans", @module.url)]
    }
    let(:expected_for_all) {
      expected_for_only_vulnerable + File.open(@plugins_file, 'r') {|file| file.readlines.collect{|line| WpPlugin.create_url_from_raw(line.chomp, @module.uri)}}.uniq!
    }

    it "should only return url from plugin_vulns_file if :only_vulnerable_ones is true" do
      targets_url = @module.plugins_targets_url(
        :only_vulnerable_ones => true,
        :plugin_vulns_file => @plugin_vulns_file
      )

      targets_url.should_not be_empty
      targets_url.sort.should === expected_for_only_vulnerable.sort
    end

    it "should return both url from plugins_file and plugin_vulns_file" do
      targets_url = @module.plugins_targets_url(
        :plugin_vulns_file => @plugin_vulns_file,
        :plugins_file => @plugins_file
      )

      targets_url.should_not be_empty
      targets_url.sort.should === expected_for_all.sort
    end
  end

  describe "#plugins_from_aggressive_detection" do

    before :each do
      @targets_url = @module.plugins_targets_url(
        :plugin_vulns_file => @plugin_vulns_file,
        :plugins_file => @plugins_file
      )
      # Point all targets to a 404
      @targets_url.each do |target_url|
        stub_request(:get, target_url).to_return(:status => 404)
      end
    end

    after :each do
      @passive_detection_fixture = SPEC_FIXTURES_DIR + "/empty-file" unless @passive_detection_fixture

      stub_request_to_fixture(:url => @wp_url, :fixture => @passive_detection_fixture)

      @module.plugins_from_aggressive_detection(
        :plugins_file => @plugins_file,
        :plugin_vulns_file => @plugin_vulns_file
      ).sort.should === @expected_plugins.sort
    end

    it "should return an empty array" do
      @expected_plugins = []
    end

    it "should return an array with 3 WpPlugin (1 detected from passive method)" do
      @expected_plugins = []

      @targets_url.sample(2).each do |target_url|
        @expected_plugins << WpPlugin.new(target_url)
        stub_request(:get, target_url).to_return(:status => 200)
      end

      @passive_detection_fixture = @fixtures_dir + "/passive_detection/one_plugin.htm"
      @expected_plugins << WpPlugin.new("http://example.localhost/wp-content/plugins/comment-info-tip/")
    end

    # testing response codes
    WpPlugins.valid_response_codes.each do |valid_response_code|
      it "should detect the plugin if the reponse.code is #{valid_response_code}" do
        @expected_plugins = []

        plugin_url = @targets_url.sample
        @expected_plugins << WpPlugin.new(plugin_url)
        stub_request(:get, plugin_url).to_return(:status => valid_response_code)
      end
    end
  end
end
