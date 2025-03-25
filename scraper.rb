require 'nokogiri'
require 'net/http'
require 'json'

def get(url)
  uri  = URI url
  resp = Net::HTTP.get_response uri
  body = resp.body
  JSON.parse body
end

API_HOST = "https://www.autotrader.co.uk"
API_PATH = "/results-car-search"

def build_params(page:)
  # NOTE: De-hardcode make, year, postcode, and distance into external parameters loaded from a YAML config
  make = "TOYOTA"
  year = 2016
  postcode = "E145AB"
  # distance = 50
  distance = 10

  params =  "page=#{page}&make=#{make}&year-from=#{year}"
  params += "&postcode=#{postcode}&radius=#{distance}"
  params += "&transmission=Automatic"
end

def search(params:)
  url    = "#{API_HOST}#{API_PATH}?#{params}"
  puts "URL: #{url}"

  resp   = get url
  html   = resp.fetch "html"
  dom    = Nokogiri::HTML html

  regex = /\/classified\/advert\/20/
  links = dom.search("a").select { |li| li["href"] =~ regex }

  links.uniq! { |link| link["href"].gsub(/#.+/, '') }
  links
end

def start_search
  results = []
  1.upto(30) do |page|
    params = build_params page: page
    links  = search params: params

    # old:
    # results += links

    # new: edit:
    cars  = filter_compatible_cars links: links
    results += cars
    # ---

  end
  results
rescue JSON::ParserError
  results
end

# -----
# new code

API_PATH_CAR = "/json/fpa/initial"
API_PATH_SPEC = "/json/taxonomy/technical-specification"


def filter_compatible_cars(links:)
  links.map do |link|
    link = link["href"].split("?")[0]
    car_compatible? link: link
  end.compact
end

def parse_car_id(link:)
  link.split("/")[-1]
end

def get_car(car_id:)
  url = "#{API_HOST}#{API_PATH_CAR}/#{car_id}"
  puts "car: #{url}"
  get url
end

def get_car_details(car_id:)
  car = get_car car_id: car_id
  spec_id = car["vehicle"] && car["vehicle"]["derivativeId"]
  mileage = car["vehicle"] && car["vehicle"]["keyFacts"] && car["vehicle"]["keyFacts"]["mileage"]
  price   = car["advert"] && car["advert"]["price"]
  {
    spec_id:  spec_id,
    price:    price.sub('£', '').sub(',', '').to_i,
    mileage:  mileage,
  }
end

def get_spec(spec_id:)
  url = "#{API_HOST}#{API_PATH_SPEC}?derivative=#{spec_id}"
  # puts "spec: #{url}"
  resp = get url
end

def car_compatible?(link:)
  car_id = parse_car_id link: link
  car_details = get_car_details car_id: car_id
  spec_id = car_details.fetch(:spec_id)
  return nil unless spec_id
  return nil unless car_details.fetch :price
  spec = get_spec spec_id: spec_id

  specs = spec.fetch("techSpecs").find{ |spec| spec["specName"] == "Driver Convenience" }["specs"]
  # specs += spec.fetch("techSpecs").find{ |spec| spec["specName"] == "Safety" }["specs"]

  specs.map! { |spec| spec.downcase }

  # toyota
  compatible = specs.find{ |spec| spec.include? "lane" } || specs.find{ |spec| spec.include? "safety sense" }
  # "lane departure alert with steering control"
  # "toyota safety sense"

  # hyundai
  # "smart cruise control"

  compatible = !!compatible
  puts "compatible: #{compatible}\n\n"

  car_details[:link] = "#{API_HOST}#{link}"

  car_details if compatible
end


# bonus points, build a "cache of all spec ids and read from the cache if you already fetched a particular spec id"

# -----


results = start_search

require 'pp'
pp results

results.sort_by!{ |result| result[:price] }
results.uniq!{ |result| result[:link] }

puts "Results: #{results.size}"

pp results

results[0..12].each do |result|
  puts `"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" #{result[:link]}`
end

# File.open("index.html", "w"){ |f| f.write html }
