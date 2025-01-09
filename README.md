[![Actions Status](https://github.com/lizmat/Backtrace-Files/actions/workflows/linux.yml/badge.svg)](https://github.com/lizmat/Backtrace-Files/actions) [![Actions Status](https://github.com/lizmat/Backtrace-Files/actions/workflows/macos.yml/badge.svg)](https://github.com/lizmat/Backtrace-Files/actions) [![Actions Status](https://github.com/lizmat/Backtrace-Files/actions/workflows/windows.yml/badge.svg)](https://github.com/lizmat/Backtrace-Files/actions)

NAME
====

Backtrace::Files - turn backtrace into list of files / lines

SYNOPSIS
========

```raku
use Backtrace::Files;

.say for backtrace-files($backtrace, :context(2));

say normalize-backtrace-filename("SETTING::src/core.c/Cool.rakumod");

.say for add-source-lines(@backtrace);
```

DESCRIPTION
===========

Backtrace::Files attempts to provide an abstract interface to backtraces and the files and line numbers in those backtraces, with the `backtrace-files` subroutine. Backtraces can be given as a string, or as an `Exception` object.

It also provides two helper subroutines: one for normalizing filenames to a local system installation (with references to the Rakudo core, and references to installed modules) called `normalize-backtrace-filename`.

And another called `add-source-lines` that will fetch the source lines of a given list of filename / line-numbers pairs, with potential context lines added.

SELECTIVE IMPORTING
===================

```raku
use Backtrace::Files <backtrace-files>;  # only export sub backtrace-files
```

By default all subroutines are exported. But you can limit this to the functions you actually need by specifying the names in the `use` statement.

To prevent name collisions and/or import any subroutine with a more memorable name, one can use the "original-name:known-as" syntax. A semi-colon in a specified string indicates the name by which the subroutine is known in this distribution, followed by the name with which it will be known in the lexical context in which the `use` command is executed.

```raku
# export "backtrace-files" as "btf"
use Backtrace::Files <backtrace-files:btf>;

.say for btf($backtrace, :context(2));
```

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

The `backtrace-files` subroutine accepts a single positional argument, the source of the backtrace information. This can either be an `Exception`, a `IO::Handle` object, an `IO::Path` object, or a string.

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

normalize-backtrace-filename
----------------------------

```raku
say normalize-backtrace-filename("SETTING::src/core.c/Cool.rakumod");
```

The `normalize-backtrace-filename` subroutine is a utility subroutine that accepts a string consisting of a filename from a backtrace, and converts this to an actual filename if the file mentioned was a conceptual filename or a filename known to have missing information.

It is intended for situations where e.g. a `CATCH` block would look at the backtrace to produce a list of actual filenames.

add-source-lines
----------------

```raku
for add-source-lines($file, (10, 20)) -> (:key($file), :value(@pairs)) {
    say $file;
    for @pairs -> (:key($linenr), :value($source)) {
        say "$linenr:$source"
    }
}
```

The `add-source-lines` subroutine is a utility subroutine that will fetch the source lines indicated by pair(s) of filename and line number lists. It either accepts a filename and a list of line numbers, or a `Pair` consisting of a filename as key and a list of line numbers as value, or it accepts a list of `Pair`s with filename a list of line numbers.

It also accepts the `:context`, `:before-context`, `:after-context`, `:in-backtrace` and `:added-context` named arguments, with the same defaults as documented with the `backtrace-files` subroutine.

AUTHOR
======

Elizabeth Mattijsen <liz@raku.rocks>

Source can be located at: https://github.com/lizmat/Backtrace-Files . Comments and Pull Requests are welcome.

If you like this module, or what I’m doing more generally, committing to a [small sponsorship](https://github.com/sponsors/lizmat/) would mean a great deal to me!

COPYRIGHT AND LICENSE
=====================

Copyright 2022, 2024, 2025 Elizabeth Mattijsen

This library is free software; you can redistribute it and/or modify it under the Artistic License 2.0.

