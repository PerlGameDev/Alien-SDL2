# t/004_config.t

use Test::More tests => 1;
use Alien::SDL2;

like( Alien::SDL2->get_header_version('SDL_version.h'), qr/([0-9]+\.)*[0-9]+/, "Testing SDL_version.h" );

diag 'Core version: '.Alien::SDL2->get_header_version('SDL_version.h');
