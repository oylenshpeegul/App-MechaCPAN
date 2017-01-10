package App::MechaCPAN::Perl;

use strict;
use autodie;
use Config;
use File::Fetch qw//;
use App::MechaCPAN qw/:go/;

our @args = (
  'threads!',
  'jobs=i',
  'skip-tests!',
);

sub go
{
  my $class = shift;
  my $opts  = shift;
  my $src   = shift;
  my @argv  = shift;

  my $orig_dir = &dest_dir;
  my $dest_dir = "$orig_dir/perl";

  my ( $src_tz, $version ) = _get_targz($src);

  if ( -e -x "$dest_dir/bin/perl" )
  {
    unless ( $opts->{is_restarted_process} )
    {
      # If it exists, we're probably running it by now.
      if ( $version && $^V ne "v$version" )
      {
        info( $version,
          "perl has already been installed ($^V, not $version)" );
      }
      else
      {
        success( $version, "perl has already been installed" );
      }
    }
    return 0;
  }

  $version = "perl $version";
  info $version, "Fetching $version";

  my $src_dir = inflate_archive($src_tz);

  chdir $src_dir;

  if ( !-e 'Configure' )
  {
    my @files = glob('*');
    if ( @files > 1 )
    {
      die 'Could not find perl to configure';
    }
    chdir $files[0];
  }

  my @config
      = ( '-des', "-Dprefix=$dest_dir", "-A'eval:scriptdir=$dest_dir'", );
  my @make = ( "make", "-j" . ( $opts->{jobs} // 2 ) );

  if ( $opts->{threads} )
  {
    push @config, '-Dusethreads';
  }

  delete @ENV{qw(PERL5LIB PERL5OPT)};

  # Make sure no tomfoolery is happening with perl, like plenv shims
  $ENV{PATH} = $Config{binexp} . ":$ENV{PATH}";

  eval {
    require Devel::PatchPerl;
    info $version, "Patching $version";
    Devel::PatchPerl->patch_source();
  };

  info $version, "Configuring $version";
  run qw[sh Configure], @config;

  info $version, "Building $version";
  run @make;

  if ( !$opts->{'skip-tests'} )
  {
    info $version, "Testing $version";
    run @make, 'test_harness';
  }

  info $version, "Installing $version";
  run @make, 'install';

  success "Installed $version";

  chdir $orig_dir;

  &restart_script();

  return 0;
}

my $perl5_re = qr/^ v? 5 [.] (\d{1,2}) (?: [.] (\d{1,2}) )? $/xms;

sub _dnld_url
{
  my $version = shift;
  my $minor   = shift;
  my $mirror  = 'http://www.cpan.org/src/5.0';

  return "$mirror/perl-5.$version.$minor.tar.bz2";
}

sub _get_targz
{
  my $src = shift;

  local $File::Fetch::WARN;

  # Attempt to find the perl version if none was given
  if ( !defined $src && -f '.perl-version' )
  {
    open my $pvFH, '<', '.perl-version';
    my $pv = do { local $/; <$pvFH> };

    #($src) = $pv =~ m[($perl5_re)]xms;
  }

  # If there's no src, find the newest version.
  if ( !defined $src )
  {
    # Do a terrible job of guessing what the current version is
    use Time::localtime;
    my $year = localtime->year() + 1900;

    # 5.12 was released in 2010, and approximatly every May, a new even
    # version was released
    my $major = ( $year - 2010 ) * 2 + ( localtime->mon < 4 ? 10 : 12 );

    # Verify our guess
    {
      my $dnld = _dnld_url( $major, 0 ) . ".md5.txt";
      my $ff       = File::Fetch->new( uri => $dnld );
      my $contents = '';
      my $where    = $ff->fetch( to => \$contents );

      if ( !defined $where && $major > 12 )
      {
        $major -= 2;
        redo;
      }
    }
    $src = "5.$major";
  }

  # file

  if ( -e $src )
  {
    return ( $src, '' );
  }

  my $url;

  # URL
  if ( $src =~ url_re )
  {
    return ( $src, '' );
  }

  # CPAN
  if ( $src =~ $perl5_re )
  {
    my $version = $1;
    my $minor   = $2;

    # They probably want the latest if minor wasn't given
    if ( !defined $minor )
    {
      # 11 is the highest minor version seen as of this writing
      my @possible = ( 0 .. 15 );

      while ( @possible > 1 )
      {
        my $i = int( @possible / 2 );
        $minor = $possible[$i];
        my $dnld = _dnld_url( $version, $minor ) . ".md5.txt";
        my $ff       = File::Fetch->new( uri => $dnld );
        my $contents = '';
        my $where    = $ff->fetch( to => \$contents );

        if ( defined $where )
        {
          # The version exists, which means it's higher still
          @possible = @possible[ $i .. $#possible ];
        }
        else
        {
          # The version doesn't exit. That means higher versions don't either
          @possible = @possible[ 0 .. $i - 1 ];
        }
      }
      $minor = $possible[0];
    }

    return ( _dnld_url( $version, $minor ), "5.$version.$minor" );
  }

  die "Cannot find $src\n";
}

1;
