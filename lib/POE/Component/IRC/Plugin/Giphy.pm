package POE::Component::IRC::Plugin::Giphy;

use strict;
use warnings;

use POE::Component::IRC;
use POE::Component::IRC::Plugin qw( :ALL );
use Hijk ();
use JSON ();

sub new {
    my ($package, %args) = @_;

    my $self = bless \%args, $package;

    die "Must provide an 'api_key' argument to " . __PACKAGE__
        unless $self->{api_key};

    print STDERR __PACKAGE__ . " using API key <@{[ $self->{api_key} ]}>\n" if $self->{debug};

    return $self;
}

sub PCI_register {
    my ($self, $irc) = @_;
    my $botcmd;

    $irc->plugin_register($self, 'SERVER', 'botcmd_firstgif');
    $irc->plugin_register($self, 'SERVER', 'botcmd_randomgif');

    foreach my $plugin ( values %{ $irc->plugin_list } ){
        if ( $plugin->isa('POE::Component::IRC::Plugin::BotCommand') ){
            $botcmd = $plugin;
            last;
        }
    }
    die __PACKAGE__ . " depends on BotCommand plugin\n" unless defined $botcmd;

    $botcmd->add(firstgif  => 'usage: firstgif cat [money [...]]');
    $botcmd->add(randomgif => 'usage: randomgif [cat]');

    return 1;
}

sub PCI_unregister {
    return 1;
}

sub S_botcmd_firstgif {
    my ($self, $irc) = (shift, shift);

    my $nick = shift;
    my $channel = shift;
    my $message = shift;

    my $text = $$message // '';

    my @wanted_tags = split /\s+/, $text;
    unless (@wanted_tags){
        $irc->yield(
            notice => $$channel,
            "usage: firstgif cat [money [...]]",
        );

        return PCI_EAT_NONE;
    }

    my $response_body = '';
    eval {
        my $response = Hijk::request({
            method => 'GET',
            host => 'api.giphy.com',
            port => 80,
            path => '/v1/gifs/search',
            query_string => 'api_key=' . $self->{api_key} . '&q=' . join('+', @wanted_tags),

            head => [
                'User-Agent' => __PACKAGE__ . ' v0 (IRC bot)',
            ],
            connect_timeout => 1.0,
            read_timeout    => 3.0,
        });

        if ( exists $response->{error} ){
            $irc->yield(
                notice => $$channel,
                "Error $response->{error} while talking to giphy.com API: HTTP status $response->{status}",
            );

            return PCI_EAT_NONE;
        }

        $response_body = $response->{body};
    } or do {
        my $error = $@ || 'Zombie error (giphy.com Hijk request)';
        $error =~ s/[\r\n]+ \z//x;

        $irc->yield(
            notice => $$channel,
            "Error while performing HTTP request: <$error>",
        );

        return PCI_EAT_NONE;
    };

    my $api_response = JSON::from_json( $response_body );
    my $api_response_keys = join ',', keys %$api_response;

    my $found_total_count = $api_response->{pagination}{total_count};
    print STDERR "giphy.com found $found_total_count gifs, meta->msg is <$api_response->{meta}{msg}>\n" if $self->{debug};

    my $status = $api_response->{meta}{msg};
    if ( $status ne 'OK' ){
        $irc->yield(
            notice => $$channel,
            "Error from giphy.com: <$status>",
        );

        return PCI_EAT_NONE;
    }

    my $data = $api_response->{data};
    if ( @$data ){

        my $first_gif = $data->[0]{images}{original}{url};

        $irc->yield(
            notice => $$channel,
            "First of $found_total_count GIFs: $first_gif",
        );
    } else {
        $irc->yield(
            notice => $$channel,
            sprintf("No GIFs found for tag%s: [%s] ... :(", (@wanted_tags > 1 ? 's' : ''), join ',', @wanted_tags ),
        );
    }

    return PCI_EAT_NONE;
}

sub S_botcmd_randomgif {
    my ($self, $irc) = (shift, shift);

    my $nick = shift;
    my $channel = shift;
    my $message = shift;

    my $limit_tag = $$message // '';
    $limit_tag =~ s/\A \s+//x;
    $limit_tag =~ s/\s+ \z//x;

    my $response_body = '';
    eval {
        my $response = Hijk::request({
            method => 'GET',
            host => 'api.giphy.com',
            port => 80,
            path => '/v1/gifs/random',
            query_string => 'api_key=' . $self->{api_key} . '&tag=' . $limit_tag,

            head => [
                'User-Agent' => __PACKAGE__ . ' v0 (IRC bot)',
            ],
            connect_timeout => 1.0,
            read_timeout    => 3.0,
        });

        if ( exists $response->{error} ){
            $irc->yield(
                notice => $$channel,
                "Error $response->{error} while talking to giphy.com API: HTTP status $response->{status}",
            );

            return PCI_EAT_NONE;
        }

        $response_body = $response->{body};
    } or do {
        my $error = $@ || 'Zombie error (giphy.com Hijk request)';
        $error =~ s/[\r\n]+ \z//x;

        $irc->yield(
            notice => $$channel,
            "Error while performing HTTP request: <$error>",
        );

        return PCI_EAT_NONE;
    };

    my $api_response = JSON::from_json( $response_body );

    my $data = $api_response->{data};
    if ( ref $data eq 'ARRAY' && !@$data ){
        $irc->yield(
            notice => $$channel,
            "giphy found no images for tag <$limit_tag>!",
        );

        return PCI_EAT_NONE;
    }

    my @tags = @{ $data->{tags} };
    my $image_url = $data->{image_url};

    $irc->yield(
        notice => $$channel,
        sprintf($image_url . "%s",
            @tags
                ? ' [' . join(',', @tags) . ']'
                : ''
        ),
    );

    return PCI_EAT_NONE;
}

1;

__END__

# vim: tabstop=4 shiftwidth=4 expandtab:
