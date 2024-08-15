# Familia - 1.0.0-pre.rc1

**Organize and store ruby objects in Redis. A Ruby ORM for Redis.**

## Installation

Get it in one of the following ways:

* In your Gemfile: `gem 'familia', '>= 1.0.0-pre.rc1'`
* Install it by hand: `gem install familia`
* Or for development: `git clone git@github.com:delano/familia.git`

## Basic Example

```ruby
    class Flower < Familia::Horreum
      identifier :generate_id
      field   :token
      field   :name
      list    :owners
      set     :tags
      zset    :metrics
      hashkey :props
      string  :counter
    end
```

## More Information

* [Github](https://github.com/delano/familia)
* [Rubygems](https://rubygems.org/gems/familia)
