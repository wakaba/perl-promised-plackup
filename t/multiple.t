use strict;
use warnings;
use Path::Tiny;
use lib glob path (__FILE__)->parent->parent->child ('t_deps/modules/*/lib');
use Test::X1;
use Test::More;
use Promised::Plackup;
use Web::UserAgent::Functions qw(http_get);

my $PlackupPath = path (__FILE__)->parent->parent->child ('plackup');

sub GET (&$$$) {
  my ($code, $plackup, $path, $c) = @_;
  return Promise->new (sub {
    my ($ok, $ng) = @_;
    my $host = $plackup->get_host;
    http_get
        url => qq<http://$host$path>,
        anyevent => 1,
        cb => sub {
          my $res = $_[1];
          test {
            $ok->($code->($res));
          } $c;
        };
  });
} # GET

test {
  my $c = shift;

  my $code = q{
    return sub {
      return [200, ['Content-Type' => 'text/plain'], ['hoge fuga']];
    };
  };

  my $server1 = Promised::Plackup->new;
  $server1->set_app_code ($code);
  my $p1 = $server1->start;

  my $server2 = Promised::Plackup->new;
  $server2->set_app_code ($code);
  my $p2 = $server2->start;

  my @p;
  for ([$p1, $server1], [$p2, $server2]) {
    my ($p, $server) = @$_;
    push @p, $p->then (sub {
      return GET {
        my $res = $_[0];
        test {
          is $res->code, 200;
        } $c;
      } $server, q</>, $c;
    });
  }

  Promise->all (\@p)->then (sub {
    return Promise->all ([$server1->stop, $server2->stop]);
  })->then (sub {
    done $c;
    undef $c;
  });
} n => 2;

run_tests;

=head1 LICENSE

Copyright 2010-2012 Hatena <http://www.hatena.ne.jp/>.

Copyright 2015 Wakaba <wakaba@suikawiki.org>.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
