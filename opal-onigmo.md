## Onigmo

We tried compiling Onigmo using a simple handcrafted libc with no memory management
so as to reduce the size. This plan backfired (rightfully so), now we use wasi-libc:

https://github.com/WebAssembly/wasi-libc

The library is made to be able to use either of them, but use of wasi-libc is highly
encouraged.

## Opal-WebAssembly

The library has advanced beyond just being usable for this project. It should be quite
compatible with Ruby-FFI allowing C API bindings across all Ruby implementations. There
are some minor incompatibilities though.

Ruby-FFI assumes a shared memory model. WebAssembly has different memory spaces for a
calling process and each library. This makes some assumptions false.

For instance, for the following code, we don't know which memory space to use:

    FFI::MemoryPointer.new(:uint8, 1200)

This requires us to use a special syntax, like:

    LibraryName.context do
      FFI::MemoryPointer.new(:uint8, 1200)
    end

This context call makes it clear that we want this memory to be alocated in the
"LibraryName" space.

Another thing is that a call like the following:

    FFI::MemoryPointer.from_string("Test string")

Would not allocate the memory, but share the memory between the calling process and
the library. In Opal-WebAssembly we must allocate the memory. Now, another issue comes
into play. In regular Ruby a call similar to this should allocate the memory and clear
it later, once the object is destroyed. In our case, we can't really access Javascript's
GC. This means we always need to free the memory ourselves.

Due to some Opal inadequacies, we can't interface floating-point fields in structs. This
doesn't happen in Onigmo, but if needed in the future, a pack/unpack implementation for
those will be needed.

Chromium browser doesn't allow us to load WebAssembly modules larger than 4KB synchronously.
This means that we had to implement some methods for awaiting the load. This also means,
that in the browser we can't use the code in a following way:

    <script src='file.js'></script>
    <script>
        Opal.Library.$new();
    </script>

This approach works in Node and possibly in other browsers, but Chromium requires us to
do it this way:

    <script src='file.js'></script>
    <script>
        Opal.WebAssembly.$wait_for("library-wasm").then(function() {
            Opal.Library.$new();
        });
    </script>

There are certain assumptions of how a library should be loaded on Opal side, but for that
please read how interscript/lib/interscript/opal/entrypoint.rb works.

## Opal-Onigmo

Our initial plan assumed upstreaming the code later on. I don't think it will be
possible or healthy. This library should stay as a separate gem for a couple of reasons.

First is that due to the memory issues, we aren't able to make it work as a drop-in
replacement. We need to manually call an #ffi_free method. Eg:

    re = Onigmo::Regexp.new("ab+")
    # use the regular expression
    re.ffi_free # free it afterwards and not use it anymore

At early stages our implementation of Opal-Onigmo we didn't consider the memory a
problem. When hit with a real world problem, we found out, that it's a severe issue and
needs to be dealt with. As far as we know, the library doesn't leak any memory if the
regular expression memory is managed correctly.

The second is that after all, we don't really have a way of caching the compiled Regexps.
Furthermore, Onigmo compiled with WASM may not be as performant as the highly optimized JS
regexp engine. In this case it's much better to leave it as a drop-in replacement for
those who need more correctness.

Opal-Onigmo doesn't implement all the methods for Ruby Regexp, it is mostly meant for
completion of the Interscript project, but can be extended beyond. It implements a few
methods it needs to implement for String (this is just an option - you need to load
onigmo/core_ext manually), but most of the existing ones work without a problem. We
implemented a Regexp.exec (Javascript) method, and the rest of Opal happened to mostly
interface with it. At the current time we know that String#split won't "just" work, but
String#{index,rindex,partition,rpartition} should.

Opal-Onigmo depends on the strings being coded as UTF-16. There are two reasons to that:

1. Opal includes methods for getting the binary form of strings in various encodings,
   but only methods for UTF-16 are valid for characters beyond the Basic Multilingual
   Plane (Unicode 0x0000 to 0xffff) which are used in 2 maps.
2. Javascript uses UTF-16 strings internally.

## Interscript

Using Opal-Onigmo we made it so that it passes _all_ the tests (not counting Thai which
depend on an external process). To optimize it, we use Opal-Onigmo _only_ when the regexp
is more than a plain-text string, otherwise we try not to use Regexp at all. It also never
frees the regexps (see a previous note about #ffi_free), because we never know if a Regexp
won't be in use later on (and the Regexps are actually cached in a Hash for performance
reasons). The issue about dangling Regexps can be worked out in the future, but the JS API
will need to change again. We would need to do something like:

    Opal.Interscript.$with_a_map("map-name", function() {
        // do some work with a map
    });

This call would at the beginning allocate all the Regexps needed, and at the end, free
them all. The good news is that we would be able to somehow integrate the map loading
(along with dependencies) with such a construct.
