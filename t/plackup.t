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

for my $server (undef, 'Starman', 'Starlet', 'Twiggy', 'Twiggy::Prefork') {
  test {
    my $c = shift;
    my $plackup = Promised::Plackup->new;
    $plackup->plackup ($PlackupPath);
    $plackup->set_server ($server);
    $plackup->set_app_code (q{
      return sub {
        return [200, ['Content-Type' => 'text/plain'], ['hoge fuga']];
      };
    });
    $plackup->start->then (sub {
      return GET {
        my $res = $_[0];
        is $res->code, 200;
        is $res->content, 'hoge fuga';
      } $plackup, q</>, $c;
    })->then (sub { return $plackup->stop })
      ->then (sub { done $c; undef $c });
  } n => 2, name => $server;
}

test {
  my $c = shift;
  my $plackup = Promised::Plackup->new;
  $plackup->plackup ('bad/plackup/command/' . rand);
  $plackup->set_app_code (q{
    return sub {
      return [200, ['Content-Type' => 'text/plain'], ['hoge fuga']];
    };
  });
  $plackup->start->then (sub {
    test {
      ok 0;
    } $c;
  }, sub {
    my $result = $_[0];
    test {
      like $result, qr{Server failed to start};
    } $c;
  })->then (sub { return $plackup->stop })
    ->then (sub { done $c; undef $c });
} n => 1, name => 'bad plackup command';

test {
  my $c = shift;
  my $plackup = Promised::Plackup->new;
  $plackup->plackup ($PlackupPath);
  $plackup->set_app_code (q{
    die;
  });
  $plackup->start->then (sub {
    test {
      ok 0;
    } $c;
  }, sub {
    my $result = $_[0];
    test {
      like $result, qr{Server does not start|Server failed to start};
    } $c;
  })->then (sub { return $plackup->stop })
    ->then (sub { done $c; undef $c });
} n => 1, name => 'bad application server';

test {
  my $c = shift;
  my $plackup = Promised::Plackup->new;
  $plackup->plackup ($PlackupPath);
  $plackup->set_app_code (q{
    return sub {
      exit;
    };
  });
  $plackup->start->then (sub {
    return GET {
      my $res = $_[0];
      isnt $res->code, 200;
    } $plackup, q</>, $c;
  })->then (sub { return $plackup->stop })
    ->then (sub { done $c; undef $c });
} n => 1;

test {
  my $c = shift;
  my $plackup = Promised::Plackup->new;
  is $plackup->_cmd->{command}, 'plackup';
  is_deeply $plackup->_cmd->{args}, [
    '--host' => '127.0.0.1',
    '--port' => $plackup->get_port,
  ];
  done $c;
  undef $c;
} n => 2, name => 'command default';

test {
  my $c = shift;
  my $plackup = Promised::Plackup->new;
  $plackup->plackup ('hoge/plackup');
  $plackup->set_option ('--app' => 'path/to/app.psgi');
  $plackup->set_option ('--port' => 1244);
  $plackup->set_server ('Twiggy');
  is $plackup->_cmd->{command}, 'hoge/plackup';
  is_deeply $plackup->_cmd->{args}, [
    '--app' => 'path/to/app.psgi',
    '--port' => 1244,
    '--server' => 'Twiggy',
  ];
  done $c;
  undef $c;
} n => 2, name => 'command non-default';

test {
  my $c = shift;

  my $code = q{
    use strict;
    use warnings;
    return sub {
      return [200, ['Content-Type' => 'text/plain'], ['hoge fuga']];
    };
  };

  my $plackup = Promised::Plackup->new;
  $plackup->set_app_code ($code);

  is $plackup->_cmd->{command}, 'plackup';
  is_deeply $plackup->_cmd->{args}, [
    '--host' => '127.0.0.1',
    '--port' => $plackup->get_port,
    '-e' => $code,
  ];

  done $c;
  undef $c;
} n => 2, name => 'set_app_code';

test {
  my $c = shift;

  my $code = q{
    use strict;
    use warnings;
    return sub {
      return [200, ['Content-Type' => 'text/plain'], ['hoge fuga']];
    };
  };

  my $plackup = Promised::Plackup->new;
  $plackup->plackup ($PlackupPath);
  $plackup->set_app_code ($code);

  $plackup->start->then (sub {
    return GET {
      my $res = $_[0];
      is $res->code, 200;
    } $plackup, q</>, $c;
  })->then (sub {
    return $plackup->stop;
  })->then (sub {
    return GET {
      my $res = $_[0];
      like $res->code, qr/^59[56]$/;
    } $plackup, q</>, $c;
  })->then (sub {
    done $c;
    undef $c;
  });
} n => 2, name => 'server';

test {
  my $c = shift;
  my $plackup = Promised::Plackup->new;
  $plackup->plackup ($PlackupPath);
  $plackup->set_option ('--app' => 'bad/psgi/path/' . rand);
  $plackup->start->then (sub {
    test {
      ok 0;
    } $c;
  }, sub {
    my $result = $_[0];
    test {
      like $result, qr{failed to start};
    } $c;
  })->then (sub { return $plackup->stop })
    ->then (sub { done $c; undef $c });
} n => 1, name => 'bad psgi path';

test {
  my $c = shift;
  my $plackup = Promised::Plackup->new;
  $plackup->plackup ($PlackupPath);
  $plackup->set_app_code (q{
    my $hoge = $ENV{HOGE};
    return sub {
      return [200, ['Content-Type' => 'text/plain'], [$hoge]];
    };
  });
  $plackup->envs->{HOGE} = "ab \xFE";
  $plackup->start->then (sub {
    return GET {
      my $res = $_[0];
      is $res->code, 200;
      is $res->content, "ab \xFE";
    } $plackup, q</>, $c;
  })->then (sub { return $plackup->stop })
    ->then (sub { done $c; undef $c });
} n => 2, name => 'envs';

run_tests;

=head1 LICENSE

Copyright 2010-2012 Hatena <http://www.hatena.ne.jp/>.

Copyright 2015 Wakaba <wakaba@suikawiki.org>.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
