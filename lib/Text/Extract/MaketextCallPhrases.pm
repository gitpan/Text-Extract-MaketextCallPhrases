package Text::Extract::MaketextCallPhrases;

use strict;
use warnings;

$Text::Extract::MaketextCallPhrases::VERSION = '0.2';

use Text::Balanced      ();
use String::Unquotemeta ();

# So we don't have to maintain an identical regex
use Module::Want 0.3 ();
my $ns_regexp = Module::Want::get_ns_regexp();

sub import {
    no strict 'refs';
    *{ caller() . '::get_phrases_in_text' } = \&get_phrases_in_text;
    *{ caller() . '::get_phrases_in_file' } = \&get_phrases_in_file;
}

my $default_regexp_conf_item = [ qr/maketext\s*\(?/, sub { return substr( $_[0], -1, 1 ) eq '(' ? qr/\s*\)/ : qr/\s*\;/ } ];

sub get_phrases_in_text {

    # 3rd arg is used internally to get the line number in the 'debug_ignored_matches' results when called via get_phrases_in_file(). Don't rely on this as it may change.
    my ( $text, $conf_hr, $linenum ) = @_; # 3rd arg is used internally to get the line number in the 'debug_ignored_matches' results when called via get_phrases_in_file(). Don't rely on this as it may change.

    $conf_hr ||= {};

    if ( $conf_hr->{'encode_unicode_slash_x'} ) {
        Module::Want::have_mod('Encode') || die $@;
    }

    my @results;

    # I like this alignment better than what tidy does, seems clearer to me even if a bit overkill perhaps
    #tidyoff
    for my $regexp ( 
        $conf_hr->{'regexp_conf'} ? (
                                        $conf_hr->{'no_default_regex'} ? @{ $conf_hr->{'regexp_conf'} } 
                                                                       : ( $default_regexp_conf_item, @{ $conf_hr->{'regexp_conf'} } )
                                    ) 
                                  : ($default_regexp_conf_item)
    ) {
    #tidyon
        my $text_working_copy = $text;
        my $original_len      = length($text_working_copy);

        while ( $text_working_copy =~ m/($regexp->[0])/ ) {
            my $matched = $1;
            my $pre;
            ( $pre, $text_working_copy ) = split( $regexp->[0], $text_working_copy, 2 );

            my $offset = $original_len - length($text_working_copy);

            my $phrase;
            my $result_hr = { 'is_error' => 0, 'is_warning' => 0, 'offset' => $offset, 'regexp' => $regexp, 'matched' => $matched };

            if ( $conf_hr->{'ignore_perlish_comments'} ) {

                # ignore matches in a comment
                if ( $pre =~ m/\#/ && $pre !~ m/[\n\r]$/ ) {
                    my @lines = split( /[\n\r]+/, $pre );

                    if ( $lines[-1] =~ m/\#/ ) {
                        $result_hr->{'type'} = 'comment';
                        $result_hr->{'line'} = $linenum if defined $linenum;
                        push @{ $conf_hr->{'debug_ignored_matches'} }, $result_hr;
                        next;
                    }
                }
            }

            # ignore functions named *maketext
            if ( $text_working_copy =~ m/^\s*\{/ ) {
                $result_hr->{'type'} = 'function';
                $result_hr->{'line'} = $linenum if defined $linenum;
                push @{ $conf_hr->{'debug_ignored_matches'} }, $result_hr;
                next;
            }

            # ignore assignments to things named *maketext
            if ( $text_working_copy =~ m/^\s*=/ ) {
                $result_hr->{'type'} = 'assignment';
                $result_hr->{'line'} = $linenum if defined $linenum;
                push @{ $conf_hr->{'debug_ignored_matches'} }, $result_hr;
                next;
            }

            if ( $conf_hr->{'ignore_perlish_statement'} ) {

                # ignore a statement named *maketext (e.g. goto &XYZ::maketext;)
                if ( $text_working_copy =~ m/^\s*;/ ) {
                    $result_hr->{'type'} = 'statement';
                    $result_hr->{'line'} = $linenum if defined $linenum;
                    push @{ $conf_hr->{'debug_ignored_matches'} }, $result_hr;
                    next;
                }
            }

            ( $phrase, $text_working_copy ) = Text::Balanced::extract_variable($text_working_copy);

            if ( !$phrase ) {

                # undef $@;
                my ( $type, $inside, $opener, $closer );
                ( $phrase, $text_working_copy, undef, $type, $opener, $inside, $closer ) = Text::Balanced::extract_quotelike($text_working_copy);

                if ( defined $inside && ( $type eq 'q' || $type eq 'qq' || $type eq 'qw' ) && $inside eq '' ) {
                    $result_hr->{'is_error'} = 1;
                    $result_hr->{'type'}     = 'empty';
                    $phrase                  = $inside;
                }
                elsif ( defined $inside && $inside ) {

                    # $result_hr->{'original'} = $phrase;
                    $phrase = $inside;

                    if ( $type eq 'qw' ) {
                        ($phrase) = split( /\s+/, $phrase, 2 );
                    }
                    elsif ( $type eq 'qx' || $opener eq '`' ) {
                        $result_hr->{'is_warning'} = 1;
                        $result_hr->{'type'}       = 'command';
                    }
                    elsif ( $type eq 'm' || $type eq 'qr' || $type eq 's' || $type eq 'tr' || $opener eq '/' ) {
                        $result_hr->{'is_warning'} = 1;
                        $result_hr->{'type'}       = 'pattern';
                    }
                }
                elsif ( defined $opener && defined $inside && defined $closer && defined $phrase && $phrase eq "$opener$inside$closer" ) {

                    # $result_hr->{'original'} = $phrase;
                    $result_hr->{'is_error'} = 1;
                    $result_hr->{'type'}     = 'empty';
                    $phrase                  = $inside;
                }
                else {
                    my $is_no_arg = 0;
                    if ( defined $regexp->[1] ) {
                        if ( ref( $regexp->[1] ) eq 'CODE' ) {
                            my $rgx = $regexp->[1]->($matched);
                            if ( $text_working_copy =~ m/^$rgx/ ) {
                                $is_no_arg = 1;
                            }
                        }
                        elsif ( ref( $regexp->[1] ) eq 'Regexp' ) {
                            my $rgx = qr/^$regexp->[1]/;
                            if ( $text_working_copy =~ $rgx ) {
                                $is_no_arg = 1;
                            }
                        }
                    }

                    if ($is_no_arg) {
                        $result_hr->{'is_error'} = 1;
                        $result_hr->{'type'}     = 'no_arg';
                    }
                    elsif ( $text_working_copy =~ m/^\s*(((?:\&|\\\*)?)$ns_regexp(?:\-\>$ns_regexp)?((?:\s*\()?))/o ) {
                        $phrase = $1;
                        my $perlish = $2 || $3 ? 1 : 0;

                        $text_working_copy =~ s/\s*(?:\&|\\\*)?$ns_regexp(?:\-\>$ns_regexp)?(?:\s*\()?\s*//o;

                        $result_hr->{'is_warning'} = 1;
                        $result_hr->{'type'} = $perlish ? 'perlish' : 'bareword';
                    }
                }
            }
            else {
                $result_hr->{'is_warning'} = 1;
                $result_hr->{'type'}       = 'perlish';
            }

            if ( !defined $phrase ) {
                my $is_no_arg = 0;
                if ( defined $regexp->[1] ) {
                    if ( ref( $regexp->[1] ) eq 'CODE' ) {
                        my $rgx = $regexp->[1]->($matched);
                        if ( $text_working_copy =~ m/^$rgx/ ) {
                            $is_no_arg = 1;
                        }
                    }
                    elsif ( ref( $regexp->[1] ) eq 'Regexp' ) {
                        my $rgx = qr/^$regexp->[1]/;
                        if ( $text_working_copy =~ $rgx ) {
                            $is_no_arg = 1;
                        }
                    }
                }

                if ($is_no_arg) {
                    $result_hr->{'is_error'} = 1;
                    $result_hr->{'type'}     = 'no_arg';
                }
                else {
                    $result_hr->{'is_warning'} = 1;
                    $result_hr->{'type'}       = 'multiline';
                }
            }
            else {
                if ( $conf_hr->{'encode_unicode_slash_x'} ) {

                    # Turn Unicode string \x{} into bytes strings
                    $phrase =~ s{(\\x\{[0-9a-fA-F]+\})}{Encode::encode_utf8( eval qq{"$1"} )}eg;
                }
                else {

                    # Preserve Unicode string \x{} for unquotemeta()
                    $phrase =~ s{(\\)(x\{[0-9a-fA-F]+\})}{$1$1$2}g;
                }

                # Turn graphemes into characters to avoid quotemeta() problems
                $phrase =~ s{((:?\\x[0-9a-fA-F]{2})+)}{eval qq{"$1"}}eg;
                $phrase = String::Unquotemeta::unquotemeta($phrase) unless exists $result_hr->{'type'} && $result_hr->{'type'} eq 'perlish';
            }

            $result_hr->{'phrase'} = $phrase;

            push @results, $result_hr;
        }
    }

    return [ sort { $a->{'offset'} <=> $b->{'offset'} } @results ];
}

sub get_phrases_in_file {
    my ( $file, $regex_conf ) = @_;

    open my $fh, '<', $file or return;

    my @results;
    my $prepend       = '';
    my $linenum       = 0;
    my $in_multi_line = 0;
    my $line;    # buffer

    while ( $line = readline($fh) ) {
        $linenum++;

        my $initial_result_count = @results;
        push @results, map { $_->{'line'} = $in_multi_line ? $in_multi_line : $linenum; $_ } @{ get_phrases_in_text( $prepend . $line, $regex_conf, $linenum ) };
        my $updated_result_count = @results;

        if ( $in_multi_line && $updated_result_count == $initial_result_count ) {
            $prepend = $prepend . $line;
            next;
        }
        elsif ( $in_multi_line && $updated_result_count > $initial_result_count && $results[-1]->{'type'} ) {
            $prepend = $prepend . $line;
            pop @results;
            next;
        }
        elsif ( !$in_multi_line && @results && defined $results[-1]->{'type'} && $results[-1]->{'type'} eq 'multiline' ) {
            $in_multi_line = $linenum;
            my $trailing_partial = pop @results;

            my $offset = $trailing_partial->{'offset'} > bytes::length( $prepend . $line ) ? bytes::length( $prepend . $line ) : $trailing_partial->{'offset'};
            $prepend = $trailing_partial->{'matched'} . substr( "$prepend$line", $offset );
            next;
        }
        else {
            $in_multi_line = 0;
            $prepend       = '';
        }
    }

    close $fh;

    return \@results;
}

1;

__END__

=head1 NAME

Text::Extract::MaketextCallPhrases - Extract phrases from maketext–call–looking text

=head1 VERSION

This document describes Text::Extract::MaketextCallPhrases version 0.1

=head1 SYNOPSIS

    use Text::Extract::MaketextCallPhrases;
    my $results_ar = get_phrases_in_text($text);

    use Text::Extract::MaketextCallPhrases;
    my $results_ar = get_phrases_in_file($file);

=head1 DESCRIPTION

Well designed systems use consistent calls for localization. If you're really smart you've also used Locale::Maketext!!

You will probably have a collection of data that contains things like this:

    $locale->maketext( ... ); (perl)

    [% locale.maketext( ..., arg1 ) %] (TT)

    !!* locale%greetings+programs | ... , arg1 | *!! (some bizarre thing you've invented)

This module looks for the first argument to things that look like maketext() calls (See L</SEE ALSO>) so that you can process as needed (lint check, add to lexicon management system, etc).

By default it looks for calls to maketext(). If you use a shortcut (e.g. _()) or an unperlish format, it can do that too (You might also want to look at L</SEE ALSO> for an alernative this module).

=head1 EXPORTS

get_phrases_in_text() and get_phrases_in_file() are exported by default unless you bring it in with require() or no-import use()

    require Text::Extract::MaketextCallPhrases;

    use Text::Extract::MaketextCallPhrases ();

=head1 INTERFACE 

These functions return an array ref containg a "result hash" (described below) for each phrase found, in the order they appear in the original text.

=head2 get_phrases_in_text()

The first argument is the text you want to parse for phrases.

The second optional argument is a hashref of options. It's keys can be as follows:

=over 4

=item 'regexp_conf'

This should be an array reference. Each item in it should be an array reference with the following 2 items:

=over 4

=item 1

A regex object (i.e. qr()) that matches the beginning of the thing you are looking for.

The regex should simply match and remain simple as it gets used by the parser where and as needed. Do not anchor or capture in it!

   qr/\<cptext/

=item 2

A regex object (i.e. qr()) that matches the end of the thing you are looking for.

It can also be a coderef that gets passed the string matched by item 1 and returns the appropriate regex object (i.e. qr()) that matches the end of the thing you are looking for.

The regex should simply match and remain simple as it gets used by the parser where and as needed. Do not anchor or capture in it! If it is possible that there is space before the closing "whatever" you should include that too.

   qr/\s*\>/ 

=back

    'regexp_conf' => [
        [ qr/greetings\+programs \|/, qr/\s*\|/ ],
        [ qr/\_\(?/, sub { return substr( $_[0], -1, 1 ) eq '(' ? qr/\s*\)/ : qr/\s*\;/ } ],
    ],

=item 'no_default_regex'

If you are using 'regexp_conf' then setting this to true will avoid using the default maketext() lookup. (i.e. only use 'regexp_conf')

=item 'encode_unicode_slash_x'

Boolean (default is false) that when true will turn Unicode string notation \x{....} into a non-grapheme byte string. This will cause L<Encode>  to be loaded if needed.

Otherwise \x{....} are left in the phrase as-is.

=item 'debug_ignored_matches'

This is an array that gets aggregate debug info on matches that did not look like something that should have a phrase associated with it.

Some examples of things that might match but would not :

    sub i_heart_maketext { 1 }
    
    *i_heart_maketext = "foo";

    goto &xyz::maketext;

    print $locale->Maketext("Hello World"); # maketext() is cool

=item 'ignore_perlish_statement'

Boolean (default is false) that when true will cause matches that look like a statement to be put in 'debug_ignored_matches' instead of a result with a 'type' os 'no_arg'.

=item 'ignore_perlish_comment'

Boolean (default is false) that when true will cause matches that look like a perl comment to be put in 'debug_ignored_matches' instead of a result.

Since this is parsing arbitrary text and thus there is no real context, interpreting what is a comment or not becomes very complex and context sensitive.

If you do not want to grab phrases from commented out data and this check does not work with this text's commenting scheme then yo could instead strip comments out of the text before parsing.

=back

=head2 get_phrases_in_file()

Same as get_phrases_in_text() except it takes a path whose contents you want to process instead of text you want to process.

If it can't be opened  returns false:

    my $results = get_phrases_in_file($file) || die "Could not read '$file': $!";

=head2 The "result hash"

This hash contains the following keys that describe the phrase that was pasred.

=over 4

=item 'phrase'

The phrase in question.

=item 'offset'

The offset in the text where the phrase started.

=item 'line'

Available via get_phrases_in_file() only, not get_phrases_in_text().

The line number the offset applies to. If a phrase spans more than one line it should be the line it starts on - but you're too smart to let the phrase dictate output format right ;p?

=item 'matched'

Chunk that matched the "maketext call" regex.

=item 'regexp' 

The array reference used to match this call/phrase. It is the same thing as each array ref passed in the regexp_conf list.

=item 'is_warning'

The phrase we found wasn't a string, which is odd.

=item 'is_error'

The phrase we found looks like a mistake was made.

=item 'type'

If the phrase is a warning or error this is a keyword that highlights why the parser wants you to look at it further.

The value can be:

=over 4 

=item undef/non-existent

Was a normal string, all is well.

=item 'command'

The phrase was a backtick or qx() expression.

=item 'pattern'

The phrase was a regex or transliteration expression.

=item 'empty'

The phrase was a hardcoded empty value.

=item 'bareword'

The phrase was a bare word expression.

=item 'perlish'

The phrase was perl-like expression (e.g. a variable)

=item 'no_arg'

The call had no arguments

=item 'multiline'

The call's argument did not contain a full entity. Probably due to a multiline phrase that is cut off at the end of the text being parsed.

This should only happen in the last item and means that some data need prependeds to the next chunk you will be parsing in effort to get a complete, parsable, argument.

    my $string_1 = "maketext('I am the very model of ";
    my $string_2 = "of a modern major general.')";

    my $results = get_phrases_in_text($string_1);

    if ( $results->[-1]->{'type'} eq 'multiline' ) {
        my $trailing_partial = pop @{$results};
        $string_2 = $trailing_partial->{'matched'} . substr( $string_1, $trailing_partial->{'offset'} ) . $string_2;
    }
    push @{$results}, @{ get_phrases_in_text($string_2) };

=back

=back

=head1 DIAGNOSTICS

This module throws no warnings or errors of its own.

=head1 CONFIGURATION AND ENVIRONMENT

Text::Extract::MaketextCallPhrases requires no configuration files or environment variables.

=head1 DEPENDENCIES

L<Text::Balanced>

L<String::Unquotemeta>

L<Module::Want> (In order to re-use the "name space" regex it has - hate to maintain it in more than one place)

=head1 INCOMPATIBILITIES

None reported.

=head1 CAVEATS

If the first thing following the "call" is a comment, the phrase will not be found.

This is because these are maketext-looking calls, not necessarily perl code. Thus interpreting what is a comment or not becomes very complex and context sensitive.

See L</SEE ALSO> if you really need to support that convention (said convention seems rather silly but hey, its your code).

The result hash's values for that call are unknown (probably 'multiline' type and undef phrase). If that holds true then detecting one in the middle of your results stack is a sign of that condition.

=head1 BUGS AND LIMITATIONS

No bugs have been reported.

Please report any bugs or feature requests to
C<bug-text-extract-maketextcallphrases@rt.cpan.org>, or through the web interface at
L<http://rt.cpan.org>.

=head1 SEE ALSO

L<Locale::Maketext::Extract> it is a driver based OO parser that has a more complex and extensible interface that may serve your needs better.

=head1 AUTHOR

Daniel Muey  C<< <http://drmuey.com/cpan_contact.pl> >>

=head1 LICENCE AND COPYRIGHT

Copyright (c) 2011, Daniel Muey C<< <http://drmuey.com/cpan_contact.pl> >>. All rights reserved.

This module is free software; you can redistribute it and/or
modify it under the same terms as Perl itself. See L<perlartistic>.

=head1 DISCLAIMER OF WARRANTY

BECAUSE THIS SOFTWARE IS LICENSED FREE OF CHARGE, THERE IS NO WARRANTY
FOR THE SOFTWARE, TO THE EXTENT PERMITTED BY APPLICABLE LAW. EXCEPT WHEN
OTHERWISE STATED IN WRITING THE COPYRIGHT HOLDERS AND/OR OTHER PARTIES
PROVIDE THE SOFTWARE "AS IS" WITHOUT WARRANTY OF ANY KIND, EITHER
EXPRESSED OR IMPLIED, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE. THE
ENTIRE RISK AS TO THE QUALITY AND PERFORMANCE OF THE SOFTWARE IS WITH
YOU. SHOULD THE SOFTWARE PROVE DEFECTIVE, YOU ASSUME THE COST OF ALL
NECESSARY SERVICING, REPAIR, OR CORRECTION.

IN NO EVENT UNLESS REQUIRED BY APPLICABLE LAW OR AGREED TO IN WRITING
WILL ANY COPYRIGHT HOLDER, OR ANY OTHER PARTY WHO MAY MODIFY AND/OR
REDISTRIBUTE THE SOFTWARE AS PERMITTED BY THE ABOVE LICENCE, BE
LIABLE TO YOU FOR DAMAGES, INCLUDING ANY GENERAL, SPECIAL, INCIDENTAL,
OR CONSEQUENTIAL DAMAGES ARISING OUT OF THE USE OR INABILITY TO USE
THE SOFTWARE (INCLUDING BUT NOT LIMITED TO LOSS OF DATA OR DATA BEING
RENDERED INACCURATE OR LOSSES SUSTAINED BY YOU OR THIRD PARTIES OR A
FAILURE OF THE SOFTWARE TO OPERATE WITH ANY OTHER SOFTWARE), EVEN IF
SUCH HOLDER OR OTHER PARTY HAS BEEN ADVISED OF THE POSSIBILITY OF
SUCH DAMAGES.