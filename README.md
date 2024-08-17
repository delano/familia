# Familia - 1.0.0-rc2 (August 2024)

**Organize and store ruby objects in Redis. A Ruby ORM for Redis.**

Familia provides a powerful and flexible way to interact with Redis using Ruby objects. It's designed to make working with Redis as natural as working with Ruby classes.

## Installation

Get it in one of the following ways:

* In your Gemfile: `gem 'familia', '>= 1.0.0-rc2'`
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

## What Familia::Horreum Can Do

Familia::Horreum provides a powerful abstraction layer over Redis, allowing you to:

1. **Define Redis-backed Ruby Classes**: As shown in the example, you can easily define classes that map to Redis structures.

2. **Use Various Redis Data Types**: Familia supports multiple Redis data types:
   - `field`: For simple key-value pairs
   - `list`: For Redis lists
   - `set`: For Redis sets
   - `zset`: For Redis sorted sets
   - `hashkey`: For Redis hashes
   - `string`: For Redis strings

3. **Custom Identifiers**: Use the `identifier` method to specify how objects are uniquely identified in Redis.

4. **Automatic Serialization**: Familia handles the serialization and deserialization of your objects to and from Redis.

5. **Redis Commands as Ruby Methods**: Interact with Redis using familiar Ruby syntax instead of raw Redis commands.

6. **TTL Support**: Set expiration times for your objects in Redis.

7. **Flexible Configuration**: Configure Redis connection details, serialization methods, and more.

## Advanced Features

- **API Versioning**: Familia supports API versioning to help manage changes in your data model over time.
- **Custom Serialization**: You can specify custom serialization methods for your objects.
- **Redis URI Support**: Easily connect to Redis using URI strings.
- **Debugging Tools**: Built-in debugging capabilities to help troubleshoot Redis interactions.

## Usage Example

```ruby
# Create a new Flower
rose = Flower.new
rose.name = "Red Rose"
rose.tags << "romantic" << "red"
rose.owners.push("Alice", "Bob")
rose.save

# Retrieve a Flower
retrieved_rose = Flower.get(rose.identifier)
puts retrieved_rose.name  # => "Red Rose"
puts retrieved_rose.tags.members  # => ["romantic", "red"]
```

## More Information

* [Github](https://github.com/delano/familia)
* [Rubygems](https://rubygems.org/gems/familia)

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.
