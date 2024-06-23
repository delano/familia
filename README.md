# Familia - 0.10.2

**Organize and store ruby objects in Redis. A Ruby ORM for Redis.**

## Installation

Get it in one of the following ways:

* In your Gemfile: `gem 'familia', '>= 0.10.2'`
* Install it by hand: `gem install familia`
* Or for development: `git clone git@github.com:delano/familia.git`

## Basic Example

```ruby
    class Flower < Storable
      include Familia
      index [:token, :name]
      field  :token
      field  :name
      list   :owners
      set    :tags
      zset   :metrics
      hash   :props
      string :value, :default => "GREAT!"
    end
```

## More Information

* [Github](https://github.com/delano/familia)
* [Rubygems](https://rubygems.org/gems/familia)
