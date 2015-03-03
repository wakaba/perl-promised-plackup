use strict;
use warnings;
use Path::Tiny;
use lib glob path (__FILE__)->parent->parent->child ('t_deps/modules/*/lib');
use Test::More;
use Test::X1;
use Promised::Command;

test {
  my $c = shift;
  my $cmd = Promised::Command->new (['perl', '-e', q{
    use AnyEvent;
    use Promised::Plackup;
    my $server = Promised::Plackup->new;
    $server->set_app_code (q{return sub { };});
    my $cv = AE::cv;
    $server->start->then (sub {
      warn "\npid=@{[$server->_cmd->pid]}\n";
      exit 0;
    }, sub {
      exit 1;
    });
    $cv->recv;
  }]);
  $cmd->stderr (\my $stderr);
  $cmd->run->then (sub {
    return $cmd->wait->then (sub {
      my $run = $_[0];
      test {
        is $run->exit_code, 0, 'exit code';
      } $c;
      return Promise->new (sub {
        my ($ok, $ng) = @_;
        my $time = 0;
        my $timer; $timer = AE::timer 0, 0.5, sub {
          if (defined $stderr and $stderr =~ /^pid=[0-9]+$/m) {
            $ok->();
            undef $timer;
          } else {
            $time += 0.5;
            if ($time > 30) {
              $ng->("timeout");
              undef $timer;
            }
          }
        };
      });
    });
  })->then (sub {
    return Promise->new (sub {
      my ($ok) = @_;
      my $timer; $timer = AE::timer 0.5, 0, sub {
        $ok->();
        undef $timer;
      };
    });
  })->then (sub {
    $stderr =~ /^pid=([0-9]+)$/m;
    my $pid = $1;
    test {
      ok not (kill 0, $pid), "$pid terminated";
    } $c;
  })->catch (sub {
    warn $_[0];
    test { ok 0 } $c;
  })->then (sub {
    done $c;
    undef $c;
  });
} n => 2;

for my $signal (qw(INT TERM QUIT)) {
for my $server (undef, 'Starlet', 'Twiggy::Prefork') {
  test {
    my $c = shift;
    my $cmd = Promised::Command->new (['perl', '-e', q{
      use AnyEvent;
      use Promised::Plackup;
      my $server = Promised::Plackup->new;
      $server->set_server (shift);
      $server->set_app_code (q{return sub { };});
      my $cv = AE::cv;
      $server->start->then (sub {
        warn "\npid=@{[$server->_cmd->pid]}\n";
        return $server->_cmd->wait->then (sub {
          $cv->send;
        }, sub {
          warn $_[0];
          exit 1;
        });
      }, sub {
        warn $_[0];
        exit 1;
      });
      $cv->recv;
    }, $server]);
    $cmd->stderr (\my $stderr);
    $cmd->run->then (sub {
      return Promise->new (sub {
        my ($ok, $ng) = @_;
        my $time = 0;
        my $timer; $timer = AE::timer 0, 0.5, sub {
          if (defined $stderr and $stderr =~ /^pid=[0-9]+$/m) {
            $ok->();
            undef $timer;
          } else {
            $time += 0.5;
            if ($time > 10) {
              $ng->("timeout: [$stderr]");
              undef $timer;
            }
          }
        };
      });
    })->then (sub {
      return $cmd->send_signal ($signal);
    })->then (sub {
      return $cmd->wait->catch (sub { warn $_[0] });
    })->then (sub {
      return Promise->new (sub {
        my ($ok) = @_;
        my $timer; $timer = AE::timer 0.5, 0, sub {
          $ok->();
          undef $timer;
        };
      });
    })->then (sub {
      $stderr =~ /^pid=([0-9]+)$/m;
      my $pid = $1;
      test {
        ok not kill 0, $pid;
      } $c;
    })->catch (sub {
      warn $_[0];
      test { ok 0 } $c;
    })->then (sub {
      done $c;
      undef $c;
    });
  } n => 1, name => [$signal, $server];
}}

run_tests;

=head1 LICENSE

Copyright 2015 Wakaba <wakaba@suikawiki.org>.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
