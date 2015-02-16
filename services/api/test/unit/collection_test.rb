require 'test_helper'

class CollectionTest < ActiveSupport::TestCase
  def create_collection name, enc=nil
    txt = ". d41d8cd98f00b204e9800998ecf8427e+0 0:0:#{name}.txt\n"
    txt.force_encoding(enc) if enc
    return Collection.create(manifest_text: txt)
  end

  test 'accept ASCII manifest_text' do
    act_as_system_user do
      c = create_collection 'foo', Encoding::US_ASCII
      assert c.valid?
    end
  end

  test 'accept UTF-8 manifest_text' do
    act_as_system_user do
      c = create_collection "f\xc3\x98\xc3\x98", Encoding::UTF_8
      assert c.valid?
    end
  end

  test 'refuse manifest_text with invalid UTF-8 byte sequence' do
    act_as_system_user do
      c = create_collection "f\xc8o", Encoding::UTF_8
      assert !c.valid?
      assert_equal [:manifest_text], c.errors.messages.keys
      assert_match /UTF-8/, c.errors.messages[:manifest_text].first
    end
  end

  test 'refuse manifest_text with non-UTF-8 encoding' do
    act_as_system_user do
      c = create_collection "f\xc8o", Encoding::ASCII_8BIT
      assert !c.valid?
      assert_equal [:manifest_text], c.errors.messages.keys
      assert_match /UTF-8/, c.errors.messages[:manifest_text].first
    end
  end

  test 'create and update collection and verify file_names' do
    act_as_system_user do
      c = create_collection 'foo', Encoding::US_ASCII
      assert c.valid?
      created_file_names = c.file_names
      assert created_file_names
      assert_match /foo.txt/, c.file_names

      c.update_attribute 'manifest_text', ". d41d8cd98f00b204e9800998ecf8427e+0 0:0:foo2.txt\n"
      assert_not_equal created_file_names, c.file_names
      assert_match /foo2.txt/, c.file_names
    end
  end

  [
    [2**8, false],
    [2**18, true],
  ].each do |manifest_size, gets_truncated|
    test "create collection with manifest size #{manifest_size} which gets truncated #{gets_truncated},
          and not expect exceptions even on very large manifest texts" do
      # file_names has a max size, hence there will be no errors even on large manifests
      act_as_system_user do
        manifest_text = './blurfl d41d8cd98f00b204e9800998ecf8427e+0'
        index = 0
        while manifest_text.length < manifest_size
          manifest_text += ' ' + "0:0:veryverylongfilename000000000000#{index}.txt\n./subdir1"
          index += 1
        end
        manifest_text += "\n"
        c = Collection.create(manifest_text: manifest_text)

        assert c.valid?
        assert c.file_names
        assert_match /veryverylongfilename0000000000001.txt/, c.file_names
        assert_match /veryverylongfilename0000000000002.txt/, c.file_names
        if !gets_truncated
          assert_match /blurfl/, c.file_names
          assert_match /subdir1/, c.file_names
        end
      end
    end
  end

  test "full text search for collections" do
    # file_names column does not get populated when fixtures are loaded, hence setup test data
    act_as_system_user do
      Collection.create(manifest_text: ". acbd18db4cc2f85cedef654fccc4a4d8+3 0:3:foo\n")
      Collection.create(manifest_text: ". 37b51d194a7513e45b56f6524f2d51f2+3 0:3:bar\n")
      Collection.create(manifest_text: ". 85877ca2d7e05498dd3d109baf2df106+95+A3a4e26a366ee7e4ed3e476ccf05354761be2e4ae@545a9920 0:95:file_in_subdir1\n./subdir2/subdir3 2bbc341c702df4d8f42ec31f16c10120+64+A315d7e7bad2ce937e711fc454fae2d1194d14d64@545a9920 0:32:file1.txt 32:32:file2.txt\n./subdir2/subdir3/subdir4 2bbc341c702df4d8f42ec31f16c10120+64+A315d7e7bad2ce937e711fc454fae2d1194d14d64@545a9920 0:32:file3.txt 32:32:file4.txt")
    end

    [
      ['foo', true],
      ['foo bar', false],                     # no collection matching both
      ['foo&bar', false],                     # no collection matching both
      ['foo|bar', true],                      # works only no spaces between the words
      ['Gnu public', true],                   # both prefixes found, though not consecutively
      ['Gnu&public', true],                   # both prefixes found, though not consecutively
      ['file4', true],                        # prefix match
      ['file4.txt', true],                    # whole string match
      ['filex', false],                       # no such prefix
      ['subdir', true],                       # prefix matches
      ['subdir2', true],
      ['subdir2/', true],
      ['subdir2/subdir3', true],
      ['subdir2/subdir3/subdir4', true],
      ['subdir2 file4', true],                # look for both prefixes
      ['subdir4', false],                     # not a prefix match
    ].each do |search_filter, expect_results|
      search_filters = search_filter.split.each {|s| s.concat(':*')}.join('&')
      results = Collection.where("#{Collection.full_text_tsvector} @@ to_tsquery(?)",
                                 "#{search_filters}")
      if expect_results
        refute_empty results
      else
        assert_empty results
      end
    end
  end

  [0, 2, 4, nil].each do |ask|
    test "replication_desired reports #{ask or 2} if redundancy is #{ask}" do
      act_as_user users(:active) do
        c = collections(:collection_owned_by_active)
        c.update_attributes redundancy: ask
        assert_equal (ask or 2), c.replication_desired
      end
    end
  end

  test "create collection with properties" do
    act_as_system_user do
      c = Collection.create(manifest_text: ". acbd18db4cc2f85cedef654fccc4a4d8+3 0:3:foo\n",
                            properties: {'property_1' => 'value_1'})
      assert c.valid?
      assert_equal 'value_1', c.properties['property_1']
    end
  end
end
