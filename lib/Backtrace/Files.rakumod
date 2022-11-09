# some global variables
my $dir-sep        := $*SPEC.dir-sep;
my $setting-source := $*EXECUTABLE.parent(3).absolute ~ $dir-sep;
my $nqp-source     := $setting-source ~ 'nqp' ~ $dir-sep;
my %repo-paths;

my sub normalize-backtrace-filename(Str:D $_) {
    .subst('SETTING::',$setting-source)
    .subst(/^ \w+ '#' /, {
        my str $name = $/.Str.chop;
        %repo-paths{$name} //=
          CompUnit::RepositoryRegistry.repository-for-name($name).prefix
          ~ $dir-sep;
    })
    .subst(/^ )> 'gen/moar/stage' /, $nqp-source)
    .subst(/^ )> 'gen' /, $setting-source)
}

my proto sub add-source-lines(|) {*}
my multi sub add-source-lines($file, @lines, *%_) {
    add-source-lines [Pair.new: $file, @lines], |%_
}
my multi sub add-source-lines(Pair:D $file-lines, *%_) {
    add-source-lines [$file-lines], |%_
}
my multi sub add-source-lines(
        @file-lines,
  Int  :$context        = 0,
  Int  :$before-context = $context,
  Int  :$after-context  = $context,
  Pair :$in-backtrace,
  Pair :$added-context,
--> Seq:D) {

    # provide a cached Seq for a given filename
    my %path-lines;
    sub path-lines($filename) {
        %path-lines{$filename}:exists
          ?? %path-lines{$filename}
          !! (%path-lines{$filename} := try $filename.IO.lines)
    }

    # need context
    if $before-context || $after-context {
        @file-lines.map: -> (:key($filename), :value(@linenrs)) {
            my $context-lines := IterationBuffer.CREATE;
            with path-lines($filename) -> @lines {
                my $last := @lines.elems;

                for @linenrs -> $linenr {
                    $context-lines.push(
                      ($_ == $linenr
                        ?? $in-backtrace
                        !! $added-context
                      ).new: $_, @lines[$_ - 1]
                    ) for ($linenr - $before-context max 1)
                       .. ($linenr + $after-context  min $last);
                }
                Pair.new: $filename, $context-lines.List
            }

            # could not read lines, no sense in providing context
            else {
                Pair.new:
                  $filename,
                  @linenrs.map({$in-backtrace.new: $_, ""}).List
            }
        }
    }

    # no context needed
    else {
        @file-lines.map: {
            my $filename := .key;
            my $lines := %path-lines{$filename} //
              (%path-lines{$filename} := try $filename.IO.lines);
            $_ = Pair.new: .key, .value.map({
                                     # .lines is zero based
                $in-backtrace.new: $_, $lines[$_ - 1] // ""
            }).List;
        }
    }
}

my proto sub backtrace-files(|) {*}
my multi sub backtrace-files(IO::Handle:D $handle, *%_) {
    backtrace-files($handle.slurp(:close), |%_)
}
my multi sub backtrace-files(IO::Path:D $io, *%_) {
    backtrace-files($io.slurp, |%_)
}
my multi sub backtrace-files(
        $exception,
  Bool :$source,
  Int  :$context        = 0,
  Int  :$before-context = $context,
  Int  :$after-context  = $context,
  Pair :$in-backtrace,
  Pair :$added-context,
--> Seq:D) {

    # some record keeping vars
    my str $lastfile = "";
    my int @lines;
    my @file-lines;

    # logic to add a frame from a backtrace to the result
    my sub add(str $string, Int() $linenr) {
        my $filename = normalize-backtrace-filename($string);
        if $filename.starts-with('<' | '-') {
            # no action, not a real file
        }
        elsif $filename ne $lastfile {
            @file-lines.push: Pair.new: $lastfile, @lines.clone if $lastfile;
            $lastfile = $filename;
            @lines    = $linenr;
        }
        else {
            @lines.push: $linenr;
        }
    }

    # Use a live Exception object's backtrace
    if Exception.ACCEPTS($exception) {
        add .file, .line for $exception.backtrace;
    }

    # Determine the file / line numbers from stacktrace
    else {
        for $exception.lines -> $line {
            if $line.starts-with('  in ') {
                my str @words  = $line.words;
                my int $linenr = @words.pop.Int;             # line nr
                @words.pop;                                  # "line"
                @words.pop if @words.tail.starts-with('(');  # (module)
                add @words.pop, $linenr;
            }
            elsif $line.starts-with('   at ') {
                if $line.contains('SETTING::') {
                    my ($setting, $, $file, $linenr) = $line.words[1].split(':', 4);
                    add $setting ~ '::' ~$file, $linenr;
                }
                else {
                    add |$line.words[1].split(':', 2);
                }
            }
            elsif $line.starts-with(' from ') {
                my ($before, Int() $linenr) = $line.split(/ ":" <( \d+ /, :v, 2);
                add $before.words.skip.head, $linenr;
            }
        }
    }
    @file-lines.push: Pair.new: $lastfile, @lines if @lines;

    $source
      ?? add-source-lines(@file-lines,
           :$before-context, :$after-context, :$in-backtrace, :$added-context)
      !! @file-lines.Seq
}

my sub EXPORT(*@names) {
    Map.new: @names
      ?? @names.map: {
             if UNIT::{"&$_"}:exists {
                 UNIT::{"&$_"}:p
             }
             else {
                 my ($in,$out) = .split(':', 2);
                 if $out && UNIT::{"&$in"} -> &code {
                     Pair.new: "&$out", &code
                 }
             }
         }
      !! UNIT::.grep: {
             .key.starts-with('&') && .key ne '&EXPORT'
         }
}

=begin pod

=head1 NAME

Backtrace::Files - turn backtrace into list of files / lines

=head1 SYNOPSIS

=begin code :lang<raku>

use Backtrace::Files;

.say for backtrace-files($backtrace, :context(2));

say normalize-backtrace-filename("SETTING::src/core.c/Cool.rakumod");

.say for add-source-lines(@backtrace);

=end code

=head1 DESCRIPTION

Backtrace::Files attempts to provide an abstract interface to backtraces
and the files and line numbers in those backtraces, with the
C<backtrace-files> subroutine.  Backtraces can be given as a string, or
as an C<Exception> object.

It also provides two helper subroutines: one for normalizing filenames
to a local system installation (with references to the Rakudo core, and
references to installed modules) called C<normalize-backtrace-filename>.

And another called C<add-source-lines> that will fetch the source lines
of a given list of filename / line-numbers pairs, with potential context
lines added.

=head1 SELECTIVE IMPORTING

=begin code :lang<raku>

use Backtrace::Files <backtrace-files>;  # only export sub backtrace-files

=end code

By default all subroutines are exported.  But you can limit this to
the functions you actually need by specifying the names in the C<use>
statement.

To prevent name collisions and/or import any subroutine with a more
memorable name, one can use the "original-name:known-as" syntax.  A
semi-colon in a specified string indicates the name by which the subroutine
is known in this distribution, followed by the name with which it will be
known in the lexical context in which the C<use> command is executed.

=begin code :lang<raku>

# export "backtrace-files" as "btf"
use Backtrace::Files <backtrace-files:btf>;

.say for btf($backtrace, :context(2));

=end code

=head1 EXPORTED SUBROUTINES

=head2 backtrace-files

=begin code :lang<raku>

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

=end code

The C<backtrace-files> subroutine accepts a single positional argument,
the source of the backtrace information.  This can either be an
C<Exception>, a C<IO::Handle> object, an C<IO::Path> object, or a string.

By default, the C<backtrace-files> subroutine produces a list of C<Pair>s
of which the key is the absolute filename, and the value is a list of
line numbers of consecutive frames within the same file.  Please note
that the same filename can occur more than once, if not all calls to
code in a file where consecutive in the backtrace.

The following optional named arguments can be specified to include the
actual source of the lines as well:

=head3 :source

Indicates whether the actual source of the lines referred to in the
backtrace, should be included as well.  If specified with a true value,
then each line number will be converted into a C<Pair> with the line
number as the key, and the actual line as the value (or an empty string
if the line could not be obtained for whatever reason).

=head3 :context(N)

Indicates whether extra source lines should be added before and after
the actual line number of the backtrace.  Only makes sense if C<:source>
has been specified with a true value.  If specified, indicates the
number of lines that should be added before and after, as additional
C<Pair>s in the array keyed to the filename.  Defaults to no lines
being added.

=head3 :before-context(N)

Indicates whether extra source lines should be added B<before> the actual
line number of the backtrace.  Only makes sense if C<:source> has been
specified with a true value.  If specified, indicates the number of
lines that should be added before, as additional C<Pair>s in the array
keyed to the filename.  Defaults to whatever was (implicitely) specified
with C<:context>.

=head3 :after-context(N)

Indicates whether extra source lines should be added B<after> the actual
line number of the backtrace.  Only makes sense if C<:source> has been
specified with a true value.  If specified, indicates the number of
lines that should be added after, as additional C<Pair>s in the array
keyed to the filename.  Defaults to whatever was (implicitely) specified
with C<:context>.

=head3 :in-backtrace(Type)

Indicates the actual type that should be used to create C<Pair>s of
line number and actual source for lines that actually occurred in the
backtrace.  Only makes sense if C<:source> has been specified with a
true value.  Defaults to C<Pair>.

=head3 :added-context(Type)

Indicates the actual type that should be used to create C<Pair>s of
line number and actual source for lines that actually occurred in the
backtrace.  Only makes sense if C<:source> has been specified with a
true value.  Defaults to C<Pair>.

=head2 normalize-backtrace-filename

=begin code :lang<raku>

say normalize-backtrace-filename("SETTING::src/core.c/Cool.rakumod");

=end code

The C<normalize-backtrace-filename> subroutine is a utility subroutine
that accepts a string consisting of a filename from a backtrace, and
converts this to an actual filename if the file mentioned was a
conceptual filename or a filename known to have missing information.

It is intended for situations where e.g. a C<CATCH> block would
look at the backtrace to produce a list of actual filenames.

=head2 add-source-lines

=begin code :lang<raku>

for add-source-lines($file, (10, 20)) -> (:key($file), :value(@pairs)) {
    say $file;
    for @pairs -> (:key($linenr), :value($source)) {
        say "$linenr:$source"
    }
}

=end code

The C<add-source-lines> subroutine is a utility subroutine that will
fetch the source lines indicated by pair(s) of filename and line number
lists.  It either accepts a filename and a list of line numbers, or a
C<Pair> consisting of a filename as key and a list of line numbers as
value, or it accepts a list of C<Pair>s with filename a list of line
numbers.

It also accepts the C<:context>, C<:before-context>, C<:after-context>,
C<:in-backtrace> and C<:added-context> named arguments, with the same
defaults as documented with the C<backtrace-files> subroutine.

=head1 AUTHOR

Elizabeth Mattijsen <liz@raku.rocks>

Source can be located at: https://github.com/lizmat/Backtrace-Files .
Comments and Pull Requests are welcome.

If you like this module, or what I’m doing more generally, committing to a
L<small sponsorship|https://github.com/sponsors/lizmat/>  would mean a great
deal to me!

=head1 COPYRIGHT AND LICENSE

Copyright 2022 Elizabeth Mattijsen

This library is free software; you can redistribute it and/or modify it under the Artistic License 2.0.

=end pod

# vim: expandtab shiftwidth=4
