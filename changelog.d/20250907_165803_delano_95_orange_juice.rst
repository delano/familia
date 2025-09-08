Changed
-------

- **Performance**: Replaced stdlib JSON with OJ gem for 2-5x faster JSON operations and reduced memory allocation. All existing code remains compatible through mimic_JSON mode. PR #97

- **Encryption**: Enhanced serialization safety for encrypted fields with improved ConcealedString handling across different JSON processing modes. Strengthened protection against accidental data exposure during serialization. PR #97

Added
-----

- **Error Handling**: Added ``NotSupportedError`` for invalid serialization mode combinations in encryption subsystem. PR #97

Security
--------

- **Encryption**: Improved concealed value protection during JSON serialization, ensuring encrypted data remains properly protected across all OJ serialization modes. PR #97

AI Assistance
-------------

- Performance optimization research and OJ gem integration strategy, including compatibility analysis and testing approach for seamless stdlib JSON replacement. PR #97
