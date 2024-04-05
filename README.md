# Familia - 0.9 (2024-04-04)

**Organize and store ruby objects in Redis**


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

* [Codes](https://github.com/delano/familia)
