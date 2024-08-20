# Familia - 1.0.0-rc5 (August 2024)

**Organize and store Ruby objects in Redis. A powerful Ruby ORM (of sorts) for Redis.**

Familia provides a flexible and feature-rich way to interact with Redis using Ruby objects. It's designed to make working with Redis as natural as working with Ruby classes, while offering advanced features for complex data management.

## Installation


Get it in one of the following ways:

* In your Gemfile: `gem 'familia', '>= 1.0.0-rc4'`
* Install it by hand: `gem install familia --pre`
* Or for development: `git clone git@github.com:delano/familia.git`


## Core Concepts and Features

### 1. Defining Horreum Classes

Familia uses the concept of "Horreum" classes to represent Redis-backed objects:

```ruby
class Flower < Familia::Horreum
  identifier :token
  field :name
  list :owners
  set :tags
  zset :metrics
  hashkey :props
  string :counter
end
```

### 2. Flexible Identifiers

You can define identifiers in various ways:

```ruby
class User < Familia::Horreum
  identifier :email
  # or
  identifier -> (user) { "user:#{user.email}" }
  # or
  identifier [:type, :email]

  field :email
  field :type
end
```

### 3. Redis Data Types

Familia supports various Redis data types:

```ruby
class Product < Familia::Horreum
  string :name
  list :categories
  set :tags
  zset :ratings
  hashkey :attributes
end
```

### 4. Class-level Redis Types

You can also define Redis types at the class level:

```ruby
class Customer < Familia::Horreum
  class_sorted_set :values, key: 'project:customers'
  class_hashkey :projects
  class_list :customers, suffix: []
  class_string :message
end
```

### 5. Automatic Expiration

Use the expiration feature to set TTL for objects:

```ruby
class Session < Familia::Horreum
  feature :expiration
  ttl 180.minutes
end
```

### 6. Safe Dumping for APIs

Control which fields are exposed when serializing objects:

```ruby
class User < Familia::Horreum
  feature :safe_dump

  @safe_dump_fields = [
    :id,
    :username,
    {full_name: ->(user) { "#{user.first_name} #{user.last_name}" }}
  ]
end
```

### 7. Quantization for Time-based Data

Use quantization for time-based metrics:

```ruby
class DailyMetric < Familia::Horreum
  feature :quantization
  string :counter, ttl: 1.day, quantize: [10.minutes, '%H:%M']
end
```

### 8. Custom Methods and Logic

Add custom methods to your Horreum classes:

```ruby
class User < Familia::Horreum
  def full_name
    "#{first_name} #{last_name}"
  end

  def active?
    status == 'active'
  end
end
```

### 9. Custom Methods and Logic

You can add custom methods to your Horreum classes:

```ruby
class Customer < Familia::Horreum
  def active?
    verified && !reset_requested
  end
end

class Session < Familia::Horreum
  def external_identifier
    elements = [ipaddress || 'UNKNOWNIP', custid || 'anon']
    @external_identifier ||= Familia.generate_sha_hash(elements)
  end
end
```
### 10. Open-ended Serialization

```ruby
class ComplexObject < Familia::Horreum
  def to_redis
    custom_serialization_method
  end

  def self.from_redis(data)
    custom_deserialization_method(data)
  end
end
```

### 11. Transactional Operations

```ruby
user.transaction do |conn|
  conn.set("user:#{user.id}:status", "active")
  conn.zadd("active_users", Time.now.to_i, user.id)
end
```


## Usage Examples

### Creating and Saving Objects

```ruby
flower = Flower.create(name: "Red Rose", token: "rrose")
flower.owners.push("Alice", "Bob")
flower.tags.add("romantic")
flower.metrics.increment("views", 1)
flower.props[:color] = "red"
flower.save
```

### Retrieving and Updating Objects

```ruby
rose = Flower.from_identifier("rrose")
rose.name = "Pink Rose"
rose.save
```

### Using Safe Dump

```ruby
user = User.create(username: "rosedog", first_name: "Rose", last_name: "Dog")
user.safe_dump
# => {id: "user:rosedog", username: "rosedog", full_name: "Rose Dog"}
```

### Working with Time-based Data

```ruby
metric = DailyMetric.new
metric.counter.increment  # Increments the counter for the current hour
```

### Bulk Operations

```ruby
Flower.multiget("rrose", "tulip", "daisy")
```

### Transactional Operations

```ruby
user.transaction do |conn|
  conn.set("user:#{user.id}:status", "active")
  conn.zadd("active_users", Time.now.to_i, user.id)
end
```

## Conclusion

Familia provides a powerful and flexible way to work with Redis in Ruby applications. Its features like automatic expiration, safe dumping, and quantization make it suitable for a wide range of use cases, from simple key-value storage to complex time-series data management.

For more information, visit:
- [Github Repository](https://github.com/delano/familia)
- [RubyGems Page](https://rubygems.org/gems/familia)

Contributions are welcome! Feel free to submit a Pull Request.
