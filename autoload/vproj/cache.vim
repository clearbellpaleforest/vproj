vim9script

# Cache module with TTL (time-to-live) expiration.
# Each named cache stores key-value pairs with expiration timestamps.

# Module-level dict: Caches (name -> {ttl, entries dict})
export var Caches: dict<any> = {}

# Create a named cache with specified TTL
export def Create(name: string, ttl_seconds: number)
  Caches[name] = {ttl: ttl_seconds, entries: {}}
enddef

# Store a value with expiration
export def Set(name: string, key: string, value: any)
  if !Caches->has_key(name)
    return
  endif
  var cache = Caches[name]
  cache.entries[key] = {
    value: value,
    expires_at: reltimefloat(reltime()) + cache.ttl
  }
enddef

# Get a value or v:null if expired/missing
export def Get(name: string, key: string): any
  if !Caches->has_key(name)
    return v:null
  endif
  var cache = Caches[name]
  if !cache.entries->has_key(key)
    return v:null
  endif
  var entry = cache.entries[key]
  if reltimefloat(reltime()) > entry.expires_at
    remove(cache.entries, key)
    return v:null
  endif
  return entry.value
enddef

# Clear all entries in a named cache
export def Invalid(name: string)
  if Caches->has_key(name)
    Caches[name].entries = {}
  endif
enddef
