# Ruby & WASM - POC

## Background
Intended to generate code in Ruby, it will (hopefully) be used by Ruby developers.
I believe that the best way to keep an open-source project maintainable, is to have its users likely to maintain it.<br>
In the C# plugin I wrote for SQLC, I used C# Roslyn to generate my code.
When coming to implement a Ruby plugin, I wanted to take a similar approach.

## The Blocker
In order to have a production SQLC plugin, we need to publish it as a standalone WASM file.
The approach I took was using the [rbwasm CLI](https://github.com/ruby/ruby.wasm) which was the only viable option I
found. <br>
After a lot of other errors that I did solve, I reached the error below and after some thorough investigation
I called quits on this angle - for now.

```text
./build/checkouts/3.2/dln.c:275:5: error: use of undeclared identifier 'Dl_info'
  275 |     Dl_info dli;
      |     ^
./build/checkouts/3.2/dln.c:279:9: error: call to undeclared function 'dladdr'; ISO C99 and later do not support implicit function declarations [-Wimplicit-function-declaration]
  279 |     if (dladdr(ex, &dli)) {
      |         ^
./build/checkouts/3.2/dln.c:279:21: error: use of undeclared identifier 'dli'
  279 |     if (dladdr(ex, &dli)) {
      |                     ^
./ruby-wasm-poc/build/checkouts/3.2/dln.c:280:20: error: use of undeclared identifier 'dli'
  280 |         *libname = dli.dli_fname;
      |                    ^
4 errors generated.
```

## Solution?
I reached the conclusion that, at this point, it's not worth the effort trying to get rbwasm to work for me,
So I decided not to let it block releasing a Ruby plugin, and I reused the code from my C# plugin to generate Ruby,
taking a vert Roslyn-inspired approach for it.

### Going Forward
While the C# code works just fine, I think using Ruby to generate Ruby is a much cleaner approach then using C# to do
so, especially in the case of Ruby which is well known in its superb metaprogramming capabilities.
Of course contributions to the project will be welcome in general, but more specifically - if anyone is interested in 
cooperating on the rbwasm approach, or some other approach that results in a Ruby code that is packaged in WASM file -
you're more then welcome to contact me.
