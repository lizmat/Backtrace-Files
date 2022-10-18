[![Actions Status](https://github.com/lizmat/Backtrace-Files/actions/workflows/test.yml/badge.svg)](https://github.com/lizmat/Backtrace-Files/actions)

NAME
====

Backtrace::Files - turn backtrace into list of files / lines

SYNOPSIS
========

```raku
use Backtrace::Files;

.say for backtrace-files($backtrace, :context(2));
```

DESCRIPTION
===========

Backtrace::Files attempts to provide an abstract interface to the files in which an execution error occurred. It exports a single subroutine `backtrace-files`, which produces a list of filename and lines.

EXPORTED SUBROUTINES
====================

backtrace-files
---------------

```raku
# show file / linenrs of given backtrace
for backtrace-files($backtrace) -> (:key($file), :value(@lines)) {
    say "$file: @lines.join(',')";
}

# show file / linenrs / actual lines of given backtrace
for backtrace-files($backtrace, :source) -> (:key($file), :value(@lines)) {
    say "$file:";
    for @lines -> (:key($linenr), :value($line)) {
        say "$linenr: $line";
    }
    say "";
}
```

By default, the `backtrace-files` subroutine produces a list of `Pair`s of which the key is the absolute filename, and the value is a list of line numbers of consecutive frames within the same file. Please note that the same filename can occur more than once, if not all calls to code in a file where consecutive in the backtrace.

The following optional named arguments can be specified to include the actual source of the lines as well:

### :source

Indicates whether the actual source of the lines referred to in the backtrace, should be included as well. If specified with a true value, then each line number will be converted into a `Pair` with the line number as the key, and the actual line as the value (or an empty string if the line could not be obtained for whatever reason).

### :context(N)

Indicates whether extra source lines should be added before and after the actual line number of the backtrace. Only makes sense if `:source` has been specified with a true value. If specified, indicates the number of lines that should be added before and after, as additional `Pair`s in the array keyed to the filename. Defaults to no lines being added.

### :before-context(N)

Indicates whether extra source lines should be added **before** the actual line number of the backtrace. Only makes sense if `:source` has been specified with a true value. If specified, indicates the number of lines that should be added before, as additional `Pair`s in the array keyed to the filename. Defaults to whatever was (implicitely) specified with `:context`.

### :after-context(N)

Indicates whether extra source lines should be added **after** the actual line number of the backtrace. Only makes sense if `:source` has been specified with a true value. If specified, indicates the number of lines that should be added after, as additional `Pair`s in the array keyed to the filename. Defaults to whatever was (implicitely) specified with `:context`.

### :in-backtrace(Type)

Indicates the actual type that should be used to create `Pair`s of line number and actual source for lines that actually occurred in the backtrace. Only makes sense if `:source` has been specified with a true value. Defaults to `Pair`.

### :added-context(Type)

Indicates the actual type that should be used to create `Pair`s of line number and actual source for lines that actually occurred in the backtrace. Only makes sense if `:source` has been specified with a true value. Defaults to `Pair`.

AUTHOR
======

Elizabeth Mattijsen <liz@raku.rocks>

Source can be located at: https://github.com/lizmat/Backtrace-Files . Comments and Pull Requests are welcome.

If you like this module, or what I’m doing more generally, committing to a [small sponsorship](https://github.com/sponsors/lizmat/) would mean a great deal to me!

COPYRIGHT AND LICENSE
=====================

Copyright 2022 Elizabeth Mattijsen

This library is free software; you can redistribute it and/or modify it under the Artistic License 2.0.

