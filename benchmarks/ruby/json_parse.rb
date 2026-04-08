# JSON parse benchmark — parse array of objects, sum "value" fields
require 'json'

NUM_OBJECTS = 50000

parts = (0...NUM_OBJECTS).map { |i| %Q({"id":#{i},"value":#{100 + (i % 1000)}}) }
json_str = "[" + parts.join(",") + "]"
entries = JSON.parse(json_str)
total = entries.sum { |e| e["value"] }
puts "len=#{json_str.length} sum=#{total}"
