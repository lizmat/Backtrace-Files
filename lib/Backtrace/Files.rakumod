# some global variables
my $dir-sep        := $*SPEC.dir-sep;
my $setting-source := $*EXECUTABLE.parent(3).absolute ~ $dir-sep;
my %repo-paths;

my proto sub backtrace-files(|) is export {*}
my multi sub backtrace-files(IO::Handle:D $handle, *%_) {
    backtrace-files($handle.slurp(:close), |%_)
}
my multi sub backtrace-files(IO::Path:D $io, *%_) {
    backtrace-files($io.slurp, |%_)
}
my multi sub backtrace-files(
  Str:D $backtrace,
  Bool :$source,
  Int  :$context        = 0,
  Int  :$before-context = $context,
  Int  :$after-context  = $context,
  Pair :$in-backtrace,
  Pair :$added-context,
--> Seq:D) is export {

    # some record keeping vars
    my str $lastfile = "";
    my int @lines;
    my @file-lines;

    # logic to add a frame from a backtrace to the result
    my sub add(str $string, Int() $linenr) {
        my $filename = $string
          .subst(/^ \w+ '#' /, {
              my str $name = $/.Str.chop;
              %repo-paths{$name} //=
                CompUnit::RepositoryRegistry.repository-for-name($name).prefix
                  ~ $dir-sep;
          })
          .subst(/^ )> 'gen/moar/stage' /, $setting-source ~ 'nqp' ~ $dir-sep)
          .subst(/^ )> 'gen' /, $setting-source)
        ;
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

    # Determine the file / line numbers
    for $backtrace.lines {
        my $line := .subst('SETTING::',$setting-source);

        if $line.starts-with('  in ') {
            my str @words  = $line.words;
            my int $linenr = @words.pop.Int;             # line nr
            @words.pop;                                  # "line"
            @words.pop if @words.tail.starts-with('(');  # (module)
            add @words.pop, $linenr;
        }
        elsif $line.starts-with('   at ') {
            add |$line.words[1].split(':', 2);
        }
        elsif $line.starts-with(' from ') {
            my ($before, Int() $linenr) = $line.split(/ ":" <( \d+ /, :v, 2);
            add $before.words.skip.head, $linenr;
        }
    }
    @file-lines.push: Pair.new: $lastfile, @lines if @lines;

    if $source {

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
                    my $end := @lines.end;

                    for @linenrs -> $linenr {
                        $context-lines.push(
                          ($_ == $linenr
                            ?? $in-backtrace
                            !! $added-context
                          ).new: $_, @lines[$_ - 1]
                        ) for ($linenr - $before-context max 1)
                           .. ($linenr + $after-context  min $end);
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

    # don't want the actual source, just the line numbers
    else {
        @file-lines.Seq
    }
}

=begin pod

=head1 NAME

Backtrace::Files - turn backtrace into list of files / lines

=head1 SYNOPSIS

=begin code :lang<raku>

use Backtrace::Files;

.say for backtrace-files($backtrace, :context(2));

=end code

=head1 DESCRIPTION

Backtrace::Files attempts to provide an abstract interface to the files
in which an execution error occurred.  It exports a single subroutine
C<backtrace-files>, which produces a list of filename and lines.

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
C<IO::Handle> object, an C<IO::Path> object, or a string.

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
