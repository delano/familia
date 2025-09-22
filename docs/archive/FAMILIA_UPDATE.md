# Familia v2.0.0-pre Series Update Overview

**Familia** is a Ruby ORM for Redis/Valkey that provides object mapping and persistence capabilities. This document summarizes the major updates from v2.0.0-pre through v2.0.0-pre7, representing a significant evolution with new features, security enhancements, and architectural improvements.

## Version Summary

| Version | Focus | Key Features |
|---------|-------|-------------|
| v2.0.0-pre | Foundation | Modern API, Valkey support, connection pooling |
| v2.0.0-pre5 | Security | Encrypted fields, transient fields, RedactedString |
| v2.0.0-pre6 | Architecture | Horreum reorganization, enhanced persistence |
| v2.0.0-pre7 | Relationships | Comprehensive relationship system, permissions |

---

## v2.0.0-pre - Foundation Release

### Major API Modernization
- **Complete API redesign** for clarity and modern Ruby conventions
- **Valkey compatibility** alongside traditional Valkey/Redis support
- **Ruby 3.4+ modernization** with fiber and thread safety improvements
- **Connection pooling foundation** with provider pattern architecture

### Security & Dependency Management
- **Critical security fixes** in Ruby workflow vulnerabilities
- **Systematic dependency resolution** via multi-constraint optimization
- **GitHub Actions security hardening** with matrix optimization

### Documentation Infrastructure
- **YARD documentation workflow** with automated GitHub Pages deployment
- **Comprehensive wiki system** with structured documentation
- **Developer-focused guides** for implementation and usage

---

## v2.0.0-pre5 - Security Enhancement Release

### Encrypted Fields System
- **Field-level encryption** with transparent access patterns
- **Multiple encryption providers**:
  - XChaCha20-Poly1305 (preferred, requires rbnacl)
  - AES-256-GCM (fallback, OpenSSL-based)
- **Field-specific key derivation** for cryptographic domain separation
- **Configurable key versioning** supporting key rotation

```ruby
class Vault < Familia::Horreum
  feature :encrypted_fields

  field :name                    # Plaintext
  encrypted_field :secret_key    # Encrypted at rest
  encrypted_field :api_token     # Transparent access
end
```

### Transient Fields & RedactedString
- **Non-persistent field storage** for sensitive runtime data
- **RedactedString wrapper** preventing accidental logging/serialization
- **Memory-safe handling** of sensitive data in Ruby objects
- **API-safe serialization** excluding transient fields

```ruby
class User < Familia::Horreum
  feature :transient_fields

  field :email
  transient_field :password      # Never persisted
  transient_field :session_token # Runtime only
end
```

### Connection Pooling Enhancement
- **Connection provider pattern** for flexible pooling strategies
- **Multi-database support** with intelligent pool management
- **Thread-safe connection handling** for concurrent applications
- **Configurable pool sizing** and timeout management

---

## v2.0.0-pre6 - Architecture Enhancement Release

### Horreum Architecture Reorganization
- **Modular class structure** with cleaner separation of concerns
- **Enhanced feature system** with dependency management
- **Improved inheritance patterns** for better code organization
- **Streamlined base class functionality**

### Enhanced Persistence Operations
- **New `save_if_not_exists` method** for conditional persistence
- **Atomic persistence operations** with transaction support
- **Enhanced error handling** for persistence failures
- **Improved data consistency** guarantees

### Security Improvements
- **Encryption field security hardening** with additional validation
- **Enhanced memory protection** for sensitive data handling
- **Improved key management** patterns and best practices
- **Security test suite expansion** with comprehensive coverage

---

## v2.0.0-pre7 - Relationships & Permissions Release

### Comprehensive Relationships System
- **Three relationship types** optimized for different use cases:
  - `participates_in` - Multi-presence tracking with score encoding
  - `indexed_by` - O(1) hash-based lookups
  - `member_of` - Bidirectional membership with collision-free naming

```ruby
class Customer < Familia::Horreum
  feature :relationships

  identifier_field :custid
  field :custid, :name, :email

  # Define collections
  set :domains
  participates_in :active_users, type: :sorted_set
end

class Domain < Familia::Horreum
  feature :relationships

  identifier_field :domain_id
  field :domain_id, :name

  # Bidirectional relationship
  member_of Customer, :domains, type: :set
end
```

### Categorical Permission System
- **Bit-encoded permissions** for efficient storage and querying
- **Time-based permission scoring** for temporal access control
- **Permission tier hierarchies** with inheritance patterns
- **Scalable permission management** for large object collections

### Advanced Relationship Features
- **Score-based sorting** with custom scoring functions
- **Permission-aware queries** filtering by access levels
- **Relationship validation framework** ensuring data integrity
- **Performance optimizations** for large-scale relationship operations

---

## Breaking Changes & Migration

### v2.0.0-pre Series
- **API method renaming** for consistency and clarity
- **Configuration changes** in connection management
- **Feature activation syntax** updates for the new system
- **Identifier field declaration** syntax modernization

### Security Considerations
- **Encryption key configuration** required for encrypted fields
- **Memory handling changes** for sensitive data protection
- **Permission system migration** for existing relationship data

---

## Performance Improvements

### Connection Management
- **Pool-based connections** reducing connection overhead
- **Intelligent connection reuse** across operations
- **Concurrent operation support** with thread-safe pooling

### Relationship Operations
- **O(1) indexed lookups** for field-based queries
- **Optimized sorted set operations** for scored relationships
- **Batch relationship operations** for bulk updates
- **Memory-efficient bit encoding** for permission storage

### Feature System
- **Lazy feature loading** reducing memory footprint
- **Dependency-aware activation** preventing conflicts
- **Optimized method dispatch** for feature methods

---

## Migrating Guide Summary

### From v1.x to v2.0.0-pre
1. **Update connection configuration** to use new pooling system
2. **Migrate identifier declarations** to new syntax
3. **Update feature activations** to use `feature :name` syntax
4. **Review method calls** for renamed API methods

### Security Feature Adoption
1. **Configure encryption keys** for encrypted fields
2. **Identify sensitive fields** for encryption/transient marking
3. **Update serialization code** to handle RedactedString
4. **Implement key rotation procedures** for production systems

### Relationship System Migration
1. **Analyze existing relationships** for optimization opportunities
2. **Choose appropriate relationship types** based on usage patterns
3. **Implement permission systems** for access-controlled relationships
4. **Update queries** to use new relationship methods

---

## Next Steps & Roadmap

### Immediate (v2.0.0 Final)
- **Production stability** testing and bug fixes
- **Performance benchmarking** and optimization
- **Documentation completion** for all features
- **Migration tooling** for existing applications

### Future Releases
- **Advanced encryption features** with hardware security modules
- **Extended relationship types** for specialized use cases
- **Performance analytics** and monitoring integration
- **Cloud-native deployment** patterns and examples

---

## Resources

- [GitHub Repository](https://github.com/delano/familia)
- [Wiki Documentation](https://github.com/delano/familia/wiki)
- [API Reference](docs/wiki/API-Reference.md)
- [Implementation Guide](docs/wiki/Implementation-Guide.md)
- [Security Model](docs/wiki/Security-Model.md)
