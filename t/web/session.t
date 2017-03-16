
use strict;
use warnings;

use RT::Test tests => undef;

my ($baseurl, $agent) = RT::Test->started_ok;

my $url = $agent->rt_base_url;

# get the top page
{
    $agent->get($url);
    is ($agent->status, 200, "Loaded a page");
}

# test a login
{
    $agent->login('root' => 'password');
    # the field isn't named, so we have to click link 0
    is( $agent->status, 200, "Fetched the page ok");
    $agent->content_contains("Logout", "Found a logout link");
}

my $ids_ref = RT::Interface::Web::Session->Ids();

# Should only have one session id at this point.
is( scalar @$ids_ref, 1, 'Got just one session id');

diag 'Load session for root user';
my %session;
tie %session, 'RT::Interface::Web::Session', $ids_ref->[0];
is ( $session{'_session_id'}, $ids_ref->[0], 'Got session id ' . $ids_ref->[0] );
is ( $session{'CurrentUser'}->Name, 'root', 'Session is for root user' );

diag 'Test queues cache';
ok ( $session{'SelectObject---RT::Queue---12---CreateTicket---0'}, 'Queues cached for create ticket');
is ( $session{'SelectObject---RT::Queue---12---CreateTicket---0'}{'objects'}->[0]{'Name'},
    'General', 'General queue is in cached list' );

undef $agent;
done_testing;
