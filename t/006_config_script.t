use strict;
use warnings;
use Test::More;
use File::Temp qw(tempdir);
use File::Spec;
use Config;
use lib 'inc', 'lib';
use My::Utility qw(check_config_script);

# Exercise script-backed configuration without installing or building SDL2.
BEGIN {
  $INC{'Alien/SDL2/ConfigData.pm'} = __FILE__;
}
{
  package Alien::SDL2::ConfigData;
  our %config;
  sub config { return $config{$_[1]} }
}
use Alien::SDL2;

my $dir = tempdir('alien-sdl2-config-XXXX', TMPDIR => 1, CLEANUP => 1);
my $suffix = $^O eq 'MSWin32' ? '.bat' : '';

sub write_script {
  my ($name, $body) = @_;
  my $path = File::Spec->catfile($dir, $name . $suffix);
  open my $fh, '>', $path or die "Cannot write $path: $!";
  print {$fh} $body;
  close $fh or die "Cannot close $path: $!";
  chmod 0755, $path or die "Cannot chmod $path: $!";
  return $path;
}

for my $module (qw(Alien::SDL Alien::SDL2)) {
  my $wrapper = write_script('wrapper-' . ($module =~ /SDL2/ ? '2' : '1'),
    "use $module;\nprint $module\->config('prefix');\n");
  ok(!defined check_config_script($wrapper), "$module wrapper rejected without execution");
}

my $body = $^O eq 'MSWin32'
  ? "\@echo off\r\nif \"%1\"==\"--version\" echo 2.0.0\r\nif \"%1\"==\"--prefix\" echo $dir\r\nexit /b 0\r\n"
  : "#!/bin/sh\ncase \"\$1\" in\n--version) echo 2.0.0;;\n--prefix) echo '$dir';;\nesac\n";
my $native = write_script('native config', $body);
my $choice = check_config_script($native);
ok($choice, 'Independent config script accepted, including a path containing spaces');
is($choice->{script}, File::Spec->rel2abs($native), 'Absolute script path saved');

{
  local $ENV{PATH} = $dir . $Config::Config{path_sep} . $ENV{PATH};
  my $from_path = check_config_script('native config');
  is(($^O eq 'MSWin32' ? lc $from_path->{script} : $from_path->{script}),
    ($^O eq 'MSWin32' ? lc $choice->{script} : $choice->{script}),
    'PATH lookup also saves the absolute path');
}

my $empty = write_script('empty', $^O eq 'MSWin32'
  ? "\@echo off\r\nexit /b 0\r\n" : "#!/bin/sh\nexit 0\n");
ok(!defined check_config_script($empty), 'Successful exit without a version rejected');
ok(!defined check_config_script(File::Spec->catfile($dir, 'missing')), 'Missing script rejected');

{
  local $Alien::SDL2::ConfigData::config{script} = $native;
  local $ENV{ALIEN_SDL2_CONFIG_RUNNING};
  delete $ENV{ALIEN_SDL2_CONFIG_RUNNING};
  is(Alien::SDL2->config('version'), '2.0.0', 'Runtime uses independent config script');
  ok(!exists $ENV{ALIEN_SDL2_CONFIG_RUNNING}, 'Runtime guard restored after invocation');
  {
    local $ENV{ALIEN_SDL2_CONFIG_RUNNING} = 1;
    eval { Alien::SDL2->config('version') };
    like($@, qr/Recursive SDL2 config script invocation/, 'Inherited recursion guard stops nested invocation');
  }
  local $Alien::SDL2::ConfigData::config{script} = write_script('failing', $^O eq 'MSWin32'
    ? "\@echo off\r\nexit /b 1\r\n" : "#!/bin/sh\nexit 1\n");
  eval { Alien::SDL2->config('version') };
  like($@, qr/SDL2 config script failed/, 'Failed script produces a diagnostic');
  ok(!exists $ENV{ALIEN_SDL2_CONFIG_RUNNING}, 'Runtime guard restored after failure');
}

done_testing;
