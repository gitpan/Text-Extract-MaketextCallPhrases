use Test::More tests => 18 + ( 3 * 5 );

use Text::Extract::MaketextCallPhrases;

diag("Testing Text::Extract::MaketextCallPhrases $Text::Extract::MaketextCallPhrases::VERSION");

my $blob = <<'END_EXAMP';
return Local::Maketext::Utile::MarkPhrase::translatable('translatable() full NS');
Jabby::translatable('translatable() alt NS');
my $tan = translatable('translatable() assignment norm');my $tns =translatable('translatable() assignment no space');
my $fbl =
translatable('translatable() at beginning of line');
$bar = translatable ('translatable () space before par');
$foo = translatable 'translatable() I am no in parens, ick';
dispath(translatable('translatable() in function call'))
dispath(   translatable('translatable() in function call space')   )
This test contains the word translatable but is not a fucntion call.
<cptext 'Hello cPanel Tag'>
[% cptext("Hello cPanel TT") %]
Yo Cpanel::Exception->new('Ka boom no args') Bar
Yo Cpanel::Exception->new(
    'Ka boom next line no args'
) Bar
Yo Cpanel::Exception->new('Ka boom no args [_1]', 42) Bar
Yo Cpanel::Exception->new(
    'Ka boom next line no args [_1] [_2]', 37
    42
) Bar
END_EXAMP

my $results = get_phrases_in_text($blob);
is( $results->[0]->{'phrase'},     "translatable() full NS",                "translatable() full NS" );
is( $results->[1]->{'phrase'},     "translatable() alt NS",                 "translatable() alt NS" );
is( $results->[2]->{'phrase'},     "translatable() assignment norm",        "translatable() assignment norm" );
is( $results->[3]->{'phrase'},     "translatable() assignment no space",    "translatable() assignment no space" );
is( $results->[4]->{'phrase'},     "translatable() at beginning of line",   "translatable() at beginning of line" );
is( $results->[5]->{'phrase'},     "translatable () space before par",      "translatable () space before par" );
is( $results->[6]->{'phrase'},     "translatable() I am no in parens, ick", "translatable() I am no in parens, ick" );
is( $results->[7]->{'phrase'},     "translatable() in function call",       "translatable() in function call" );
is( $results->[8]->{'phrase'},     "translatable() in function call space", "translatable() in function call space" );
is( $results->[9]->{'phrase'},     "but",                                   "translatable in text - value" );
is( $results->[9]->{'is_warning'}, 1,                                       "translatable in text - is_warning" );
is( $results->[9]->{'type'},       'bareword',                              "translatable in text - type" );

# This is really just a sanity check that these are found, the tests for maketext() cover all sorts of odd syntax
for my $meth (qw(lextext maketext_html_context maketext_ansi_context  maketext_plain_context maketext_W3_are_cUst0M_context)) {
    my $blob    = qq{$meth('$meth() norm');dothis($meth("$meth() in function"));$meth\n'$meth() odd'\n;};
    my $results = get_phrases_in_text($blob);
    is( $results->[0]->{'phrase'}, "$meth() norm",        "$meth() found" );
    is( $results->[1]->{'phrase'}, "$meth() in function", "$meth() found again" );
    is( $results->[2]->{'phrase'}, "$meth() odd",         "$meth() found with odd call" );
}

$results = get_phrases_in_text( $blob, { cpanel_mode => 1 } );
is( $results->[10]->{'phrase'}, "Hello cPanel Tag",                    "cptext tag" );
is( $results->[11]->{'phrase'}, "Hello cPanel TT",                     "cptext TT" );
is( $results->[12]->{'phrase'}, "Ka boom no args",                     "Cpanel::Exception->new() one line no args" );
is( $results->[13]->{'phrase'}, "Ka boom next line no args",           "Cpanel::Exception->new() next line no args" );
is( $results->[14]->{'phrase'}, "Ka boom no args [_1]",                "Cpanel::Exception->new() one line w/ args" );
is( $results->[15]->{'phrase'}, "Ka boom next line no args [_1] [_2]", "Cpanel::Exception->new() next line w/ args" );
