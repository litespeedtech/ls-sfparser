#!/usr/bin/env perl
#
# Test parser by feeding it JSON tests from the test suite.

use strict;
use warnings;

use Data::Dumper;
use Getopt::Long;
use JSON qw(decode_json);

GetOptions("stop!" => \(my $stop = 1));

my $test_prog = './test-sfp';
-x $test_prog or die "$test_prog is not executable";

my %header_types = ( dictionary => 0, list => 1, item => 2, );
my $exit_status = 0;
my $test_nr = 0;

for my $json_file (@ARGV) {
    my $json = decode_json do {
        open my $handle, $json_file
                or die "cannot open $json_file for reading: $!";
        local $/;
        <$handle>;
    };
    die "json object in $json_file is not an array"
        if ref($json) ne 'ARRAY';
    for my $item (@$json) {
        unless ('ARRAY' eq ref $$item{raw}) {
            die "unexpected raw: " . Dumper($item);
        }
        my $data;
        if (@{$$item{raw}} > 1) {
            die "can item be split? ". Dumper($item) if 'item' eq $$item{header_type};
            $data = join ', ', @{$$item{raw}};
        } else {
            $data = $$item{raw}[0];
        }
        my $fail =  $$item{must_fail} ? "must" :
                    $$item{may_fail} ? "may" :
                    "no";
        my $type = $header_types{$$item{header_type}};
        ++$test_nr;
        print "test #$test_nr; named `$$item{name}'; fail: $fail, ",
            "type: $type; data: [", $data =~ s/\t/\\t/gr, "]\n";
        my $status;
        if ($data !~ /\x00/) {
            $status = system($test_prog, $type, $data);
        } else {
            $data = join '', map { sprintf "\\x%02X", ord } split //, $data;
            $status = system("echo -ne '$data' | $test_prog $type");
        }
        if ($fail eq 'must') {
            $status = not $status;
        } elsif ($fail eq 'may') {
            $status = 0;     # Who cares right? XXX
        }
        if ($status == 0) {
            print "OK\n";
        } else {
            print "FAIL\n";
        }
        print "\n";
        exit 1 if $status and $stop;
        $exit_status |= !!$status;
    }
}

exit $exit_status;
