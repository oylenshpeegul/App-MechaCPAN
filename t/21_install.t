use strict;
use FindBin;
use Test::More;
use Config;
use Cwd qw/cwd/;
use File::Temp qw/tempdir/;

use App::MechaCPAN;

my $pwd = cwd;
foreach my $dist (sort glob("$FindBin::Bin/../test_dists/*/*.tar.gz"))
{
  chdir $pwd;
  my $dir = tempdir( TEMPLATE => "$pwd/mechacpan_t_XXXXXXXX", CLEANUP => 0 );
  chdir $dir;

  my ($name) = $dist =~ m[test_dists/(.*?)/]xms;
  is(App::MechaCPAN::main('install', $dist), 0, "Can install $dist");
  is(cwd, $dir, 'Returned to whence it started');
  ok(-e "$dir/local_t/lib/perl5/$name.pm", 'Library exists as expected');
}

done_testing;