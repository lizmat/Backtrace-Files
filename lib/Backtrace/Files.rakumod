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
        add .file.words.head, .line for $exception.backtrace;
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

# vim: expandtab shiftwidth=4
