use strict;
use warnings;

use RT::Test tests => undef, config => << 'CONFIG';
Plugin('RT::Extension::Initialdata::JSON');
Set($InitialdataFormatHandlers, [ 'perl', 'RT::Extension::Initialdata::JSON' ]);
CONFIG

my @tests = (
    {
        name => 'Simple user-defined group',
        create => sub {
            my $group = RT::Group->new(RT->SystemUser);
            my ($ok, $msg) = $group->CreateUserDefinedGroup(Name => 'Staff');
            ok($ok, $msg);
        },
        absent => sub {
            my $group = RT::Group->new(RT->SystemUser);
            $group->LoadUserDefinedGroup('Staff');
            ok(!$group->Id, 'No such group');
        },
        present => sub {
            my $group = RT::Group->new(RT->SystemUser);
            $group->LoadUserDefinedGroup('Staff');
            ok($group->Id, 'Loaded group');
            is($group->Name, 'Staff', 'Group name');
            is($group->Domain, 'UserDefined', 'Domain');
        },
    },

    {
        name => 'Custom field on two queues',
        create => sub {
            my $bugs = RT::Queue->new(RT->SystemUser);
            my ($ok, $msg) = $bugs->Create(Name => 'Bugs');
            ok($ok, $msg);

            my $features = RT::Queue->new(RT->SystemUser);
            ($ok, $msg) = $features->Create(Name => 'Features');
            ok($ok, $msg);

            my $cf = RT::CustomField->new(RT->SystemUser);
            ($ok, $msg) = $cf->Create(
                Name => 'Fixed In',
                Type => 'SelectSingle',
                LookupType => RT::Queue->CustomFieldLookupType,
            );
            ok($ok, $msg);

            ($ok, $msg) = $cf->AddToObject($bugs);
            ok($ok, $msg);

            ($ok, $msg) = $cf->AddToObject($features);
            ok($ok, $msg);

            ($ok, $msg) = $cf->AddValue(Name => '0.1', Description => 'Prototype', SortOrder => '1');
            ok($ok, $msg);

            ($ok, $msg) = $cf->AddValue(Name => '1.0', Description => 'Gold', SortOrder => '10');
            ok($ok, $msg);

            # these next two are intentionally added in an order different from their SortOrder
            ($ok, $msg) = $cf->AddValue(Name => '2.0', Description => 'Remaster', SortOrder => '20');
            ok($ok, $msg);

            ($ok, $msg) = $cf->AddValue(Name => '1.1', Description => 'Gold Bugfix', SortOrder => '11');
            ok($ok, $msg);

        },
        present => sub {
            my $bugs = RT::Queue->new(RT->SystemUser);
            $bugs->Load('Bugs');
            ok($bugs->Id, 'Bugs queue loaded');
            is($bugs->Name, 'Bugs');

            my $features = RT::Queue->new(RT->SystemUser);
            $features->Load('Features');
            ok($features->Id, 'Features queue loaded');
            is($features->Name, 'Features');

            my $cf = RT::CustomField->new(RT->SystemUser);
            $cf->Load('Fixed In');
            ok($cf->Id, 'Features queue loaded');
            is($cf->Name, 'Fixed In');
            is($cf->Type, 'Select', 'Type');
            is($cf->MaxValues, 1, 'MaxValues');
            is($cf->LookupType, RT::Queue->CustomFieldLookupType, 'LookupType');

            ok($cf->IsAdded($bugs->Id), 'CF is on Bugs queue');
            ok($cf->IsAdded($features->Id), 'CF is on Features queue');
            ok(!$cf->IsAdded(0), 'CF is not global');

            my $general = RT::Queue->new(RT->SystemUser);
            $general->Load('General');
            ok(!$cf->IsAdded($general->Id), 'CF is not on General queue');

            my @values = map { {
                Name => $_->Name,
                Description => $_->Description,
                SortOrder => $_->SortOrder,
            } } @{ $cf->Values->ItemsArrayRef };

            is_deeply(\@values, [
                { Name => '0.1', Description => 'Prototype', SortOrder => '1' },
                { Name => '1.0', Description => 'Gold', SortOrder => '10' },
                { Name => '1.1', Description => 'Gold Bugfix', SortOrder => '11' },
                { Name => '2.0', Description => 'Remaster', SortOrder => '20' },
            ], 'CF values');
        },
    },
);

my $id = 0;
for my $test (@tests) {
    $id++;
    my $directory = File::Spec->catdir(RT::Test->temp_directory, "export-$id");

    # we get a lot of warnings about already-existing objects; suppress them
    # for now until we clean it up
    my $warn = $SIG{__WARN__};
    local $SIG{__WARN__} = sub {
        return if $_[0] =~ join '|', (
            qr/^Name in use$/,
            qr/^Group name '.*' is already in use$/,
            qr/^A Template with that name already exists$/,
            qr/^.* already has the right .* on .*$/,
            qr/^Invalid value for Name$/,
            qr/^Queue already exists$/,
            qr/^Use of uninitialized value in/,
        );

        # Avoid reporting this anonymous call frame as the source of the warning
        goto &$warn;
    };

    subtest "$test->{name} (ordinary creation)" => sub {
        autorollback(sub {
            $test->{absent}->() if $test->{absent};
            $test->{create}->();
            $test->{present}->() if $test->{present};
            export_initialdata($directory);
        });
    };

    subtest "$test->{name} (from initialdata)" => sub {
        autorollback(sub {
            $test->{absent}->() if $test->{absent};
            import_initialdata($directory);
            $test->{present}->() if $test->{present};
        });
    };
}

done_testing();

# vvvv   here be dragons   vvvv

sub autorollback {
    my $code = shift;

    $RT::Handle->BeginTransaction;
    {
        # avoid "Rollback and commit are mixed while escaping nested transaction" warnings
        # due to (begin; (begin; commit); rollback)
        no warnings 'redefine';
        local *DBIx::SearchBuilder::Handle::BeginTransaction = sub {};
        local *DBIx::SearchBuilder::Handle::Commit = sub {};
        local *DBIx::SearchBuilder::Handle::Rollback = sub {};

        $code->();
    }
    $RT::Handle->Rollback;
}

sub export_initialdata {
    my $directory = shift;
    local @RT::Record::ISA = qw( DBIx::SearchBuilder::Record RT::Base );

    use RT::Migrate::Serializer::JSON;
    my $migrator = RT::Migrate::Serializer::JSON->new(
        Directory          => $directory,
        Verbose            => 0,
        AllUsers           => 0,
        FollowACL          => 1,
        FollowScrips       => 1,
        FollowTransactions => 0,
    );

    $migrator->Export;
}

sub import_initialdata {
    my $directory = shift;
    my $initialdata = File::Spec->catfile($directory, "initialdata.json");

    ok(-e $initialdata, "File $initialdata exists");

    my ($rv, $msg) = RT->DatabaseHandle->InsertData( $initialdata, undef, disconnect_after => 0 );
    ok($rv, "Inserted test data from $initialdata")
        or diag "Error: $msg";
}

