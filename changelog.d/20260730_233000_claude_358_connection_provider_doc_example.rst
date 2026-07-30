Documentation
-------------

- Fixed the ``connection_provider`` examples, which ended with
  ``pool.with { |conn| conn }`` -- a connection the pool has already checked
  back in, so concurrent callers share it. #358
