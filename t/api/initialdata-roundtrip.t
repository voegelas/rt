use strict;
use warnings;

use RT::Test tests => undef, config => << 'CONFIG';
Plugin('RT::Extension::Initialdata::JSON');
Set($InitialdataFormatHandlers, [ 'perl', 'RT::Extension::Initialdata::JSON' ]);
CONFIG

my $general = RT::Queue->new(RT->SystemUser);
$general->Load('General');

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
        name => 'Group membership',
        create => sub {
            my $outer = RT::Group->new(RT->SystemUser);
            my ($ok, $msg) = $outer->CreateUserDefinedGroup(Name => 'Outer');
            ok($ok, $msg);

            my $inner = RT::Group->new(RT->SystemUser);
            ($ok, $msg) = $inner->CreateUserDefinedGroup(Name => 'Inner');
            ok($ok, $msg);

            my $user = RT::User->new(RT->SystemUser);
            ($ok, $msg) = $user->Create(Name => 'User');
            ok($ok, $msg);

            ($ok, $msg) = $outer->AddMember($inner->PrincipalId);
            ok($ok, $msg);

            ($ok, $msg) = $inner->AddMember($user->PrincipalId);
            ok($ok, $msg);
        },
        present => sub {
            my $outer = RT::Group->new(RT->SystemUser);
            $outer->LoadUserDefinedGroup('Outer');
            ok($outer->Id, 'Loaded group');
            is($outer->Name, 'Outer', 'Group name');

            my $inner = RT::Group->new(RT->SystemUser);
            $inner->LoadUserDefinedGroup('Inner');
            ok($inner->Id, 'Loaded group');
            is($inner->Name, 'Inner', 'Group name');

            my $user = RT::User->new(RT->SystemUser);
            $user->Load('User');
            ok($user->Id, 'Loaded user');
            is($user->Name, 'User', 'User name');

            ok($outer->HasMember($inner->PrincipalId), 'outer hasmember inner');
            ok($inner->HasMember($user->PrincipalId), 'inner hasmember user');
            ok($outer->HasMemberRecursively($user->PrincipalId), 'outer hasmember user recursively');
            ok(!$outer->HasMember($user->PrincipalId), 'outer does not have member user directly');
            ok(!$inner->HasMember($outer->PrincipalId), 'inner does not have member outer');
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
                LookupType => RT::Ticket->CustomFieldLookupType,
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
            ok($cf->Id, 'Fixed In CF loaded');
            is($cf->Name, 'Fixed In');
            is($cf->Type, 'Select', 'Type');
            is($cf->MaxValues, 1, 'MaxValues');
            is($cf->LookupType, RT::Ticket->CustomFieldLookupType, 'LookupType');

            ok($cf->IsAdded($bugs->Id), 'CF is on Bugs queue');
            ok($cf->IsAdded($features->Id), 'CF is on Features queue');
            ok(!$cf->IsAdded(0), 'CF is not global');
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

    {
        name => 'Custom field lookup types',
        create => sub {
            for my $type (qw/Asset Article Group Queue Ticket Transaction User/) {
                my $class = "RT::$type";
                my $cf = RT::CustomField->new(RT->SystemUser);
                my ($ok, $msg) = $cf->Create(
                    Name => "$type CF",
                    Type => "FreeformSingle",
                    LookupType => $class->CustomFieldLookupType,
                );
                ok($ok, $msg);
            }
        },
        present => sub {
            for my $type (qw/Asset Article Group Queue Ticket Transaction User/) {
                my $class = "RT::$type";
                my $cf = RT::CustomField->new(RT->SystemUser);
                $cf->Load("$type CF");
                ok($cf->Id, "loaded $type CF");
                is($cf->Name, "$type CF", 'Name');
                is($cf->Type, 'Freeform', 'Type');
                is($cf->MaxValues, 1, 'MaxValues');
                is($cf->LookupType, $class->CustomFieldLookupType, 'LookupType');
            }
        },
    },

    {
        name => 'Scrips',
        create => sub {
            my $bugs = RT::Queue->new(RT->SystemUser);
            my ($ok, $msg) = $bugs->Create(Name => 'Bugs');
            ok($ok, $msg);

            my $features = RT::Queue->new(RT->SystemUser);
            ($ok, $msg) = $features->Create(Name => 'Features');
            ok($ok, $msg);

            my $disabled = RT::Scrip->new(RT->SystemUser);
            ($ok, $msg) = $disabled->Create(
                Queue => 0,
                Description => 'Disabled Scrip',
                Template => 'Blank',
                ScripCondition => 'User Defined',
                ScripAction => 'User Defined',
                CustomIsApplicableCode => 'return "condition"',
                CustomPrepareCode => 'return "prepare"',
                CustomCommitCode => 'return "commit"',
            );
            ok($ok, $msg);
            $disabled->SetDisabled(1);

            my $stages = RT::Scrip->new(RT->SystemUser);
            ($ok, $msg) = $stages->Create(
                Description => 'Staged Scrip',
                Template => 'Transaction',
                ScripCondition => 'On Create',
                ScripAction => 'Notify Owner',
            );
            ok($ok, $msg);

            ($ok, $msg) = $stages->RemoveFromObject(0);
            ok($ok, $msg);

            ($ok, $msg) = $stages->AddToObject(
                ObjectId  => $bugs->Id,
                Stage     => 'TransactionBatch',
                SortOrder => 42,
            );
            ok($ok, $msg);

            ($ok, $msg) = $stages->AddToObject(
                ObjectId  => $features->Id,
                Stage     => 'TransactionCreate',
                SortOrder => 99,
            );
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

            my $disabled = RT::Scrip->new(RT->SystemUser);
            $disabled->LoadByCols(Description => 'Disabled Scrip');
            ok($disabled->Id, 'Disabled scrip loaded');
            is($disabled->Description, 'Disabled Scrip', 'Description');
            is($disabled->Template, 'Blank', 'Template');
            is($disabled->ConditionObj->Name, 'User Defined', 'Condition');
            is($disabled->ActionObj->Name, 'User Defined', 'Action');
            is($disabled->CustomIsApplicableCode, 'return "condition"', 'Condition code');
            is($disabled->CustomPrepareCode, 'return "prepare"', 'Prepare code');
            is($disabled->CustomCommitCode, 'return "commit"', 'Commit code');
            ok($disabled->Disabled, 'Disabled');
            ok($disabled->IsGlobal, 'IsGlobal');

            my $stages = RT::Scrip->new(RT->SystemUser);
            $stages->LoadByCols(Description => 'Staged Scrip');
            ok($stages->Id, 'Staged scrip loaded');
            is($stages->Description, 'Staged Scrip');
            ok(!$stages->Disabled, 'not Disabled');
            ok(!$stages->IsGlobal, 'not Global');

            my $bug_objectscrip = $stages->IsAdded($bugs->Id);
            ok($bug_objectscrip, 'added to Bugs');
            is($bug_objectscrip->Stage, 'TransactionBatch', 'Stage');
            is($bug_objectscrip->SortOrder, 42, 'SortOrder');

            my $features_objectscrip = $stages->IsAdded($features->Id);
            ok($features_objectscrip, 'added to Features');
            is($features_objectscrip->Stage, 'TransactionCreate', 'Stage');
            is($features_objectscrip->SortOrder, 99, 'SortOrder');

            ok(!$stages->IsAdded($general->Id), 'not added to General');
        },
    },

    {
        name => 'Unapplied Objects',
        create => sub {
            my $scrip = RT::Scrip->new(RT->SystemUser);
            my ($ok, $msg) = $scrip->Create(
                Queue => 0,
                Description => 'Unapplied Scrip',
                Template => 'Blank',
                ScripCondition => 'On Create',
                ScripAction => 'Notify Owner',
            );
            ok($ok, $msg);
            ($ok, $msg) = $scrip->RemoveFromObject(0);
            ok($ok, $msg);

            my $cf = RT::CustomField->new(RT->SystemUser);
            ($ok, $msg) = $cf->Create(
                Name        => 'Unapplied CF',
                Type        => 'FreeformSingle',
                LookupType  => RT::Ticket->CustomFieldLookupType,
            );
            ok($ok, $msg);

            my $class = RT::Class->new(RT->SystemUser);
            ($ok, $msg) = $class->Create(
                Name => 'Unapplied Class',
            );
            ok($ok, $msg);

            my $role = RT::CustomRole->new(RT->SystemUser);
            ($ok, $msg) = $role->Create(
                Name => 'Unapplied Custom Role',
            );
            ok($ok, $msg);
        },
        present => sub {
            my $scrip = RT::Scrip->new(RT->SystemUser);
            $scrip->LoadByCols(Description => 'Unapplied Scrip');
            ok($scrip->Id, 'Unapplied scrip loaded');
            is($scrip->Description, 'Unapplied Scrip');
            ok(!$scrip->Disabled, 'not Disabled');
            ok(!$scrip->IsGlobal, 'not Global');
            ok(!$scrip->IsAdded($general->Id), 'not applied to General queue');

            my $cf = RT::CustomField->new(RT->SystemUser);
            $cf->Load('Unapplied CF');
            ok($cf->Id, 'Unapplied CF loaded');
            is($cf->Name, 'Unapplied CF');
            ok(!$cf->Disabled, 'not Disabled');
            ok(!$cf->IsGlobal, 'not Global');
            ok(!$cf->IsAdded($general->Id), 'not applied to General queue');

            my $class = RT::Class->new(RT->SystemUser);
            $class->Load('Unapplied Class');
            ok($class->Id, 'Unapplied Class loaded');
            is($class->Name, 'Unapplied Class');
            ok(!$class->Disabled, 'not Disabled');
            ok(!$class->IsApplied(0), 'not Global');
            ok(!$class->IsApplied($general->Id), 'not applied to General queue');

            my $role = RT::CustomRole->new(RT->SystemUser);
            $role->Load('Unapplied Custom Role');
            ok($role->Id, 'Unapplied Custom Role loaded');
            is($role->Name, 'Unapplied Custom Role');
            ok(!$role->Disabled, 'not Disabled');
            ok(!$role->IsAdded(0), 'not Global');
            ok(!$role->IsAdded($general->Id), 'not applied to General queue');
        },
    },

    {
        name => 'Global Objects',
        create => sub {
            my $scrip = RT::Scrip->new(RT->SystemUser);
            my ($ok, $msg) = $scrip->Create(
                Queue => 0,
                Description => 'Global Scrip',
                Template => 'Blank',
                ScripCondition => 'On Create',
                ScripAction => 'Notify Owner',
            );
            ok($ok, $msg);

            my $cf = RT::CustomField->new(RT->SystemUser);
            ($ok, $msg) = $cf->Create(
                Name        => 'Global CF',
                Type        => 'FreeformSingle',
                LookupType  => RT::Ticket->CustomFieldLookupType,
            );
            ok($ok, $msg);
            ($ok, $msg) = $cf->AddToObject(RT::Queue->new(RT->SystemUser));
            ok($ok, $msg);

            my $class = RT::Class->new(RT->SystemUser);
            ($ok, $msg) = $class->Create(
                Name => 'Global Class',
            );
            ok($ok, $msg);
            ($ok, $msg) = $class->AddToObject(RT::Queue->new(RT->SystemUser));
            ok($ok, $msg);
        },
        present => sub {
            my $scrip = RT::Scrip->new(RT->SystemUser);
            $scrip->LoadByCols(Description => 'Global Scrip');
            ok($scrip->Id, 'Global scrip loaded');
            is($scrip->Description, 'Global Scrip');
            ok(!$scrip->Disabled, 'not Disabled');
            ok($scrip->IsGlobal, 'Global');
            ok(!$scrip->IsAdded($general->Id), 'not applied to General queue');

            my $cf = RT::CustomField->new(RT->SystemUser);
            $cf->Load('Global CF');
            ok($cf->Id, 'Global CF loaded');
            is($cf->Name, 'Global CF');
            ok(!$cf->Disabled, 'not Disabled');
            ok($cf->IsGlobal, 'Global');
            ok(!$cf->IsAdded($general->Id), 'not applied to General queue');

            my $class = RT::Class->new(RT->SystemUser);
            $class->Load('Global Class');
            ok($class->Id, 'Global Class loaded');
            is($class->Name, 'Global Class');
            ok(!$class->Disabled, 'not Disabled');
            ok($class->IsApplied(0), 'Global');
            ok(!$class->IsApplied($general->Id), 'not applied to General queue');
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

    my $name    = delete $test->{name};
    my $create  = delete $test->{create};
    my $absent  = delete $test->{absent};
    my $present = delete $test->{present};
    fail("Unexpected keys for test #$id ($name): " . join(', ', sort keys %$test)) if keys %$test;

    subtest "$name (ordinary creation)" => sub {
        autorollback(sub {
            $absent->() if $absent;
            $create->();
            $present->() if $present;
            export_initialdata($directory);
        });
    };

    subtest "$name (from initialdata)" => sub {
        autorollback(sub {
            $absent->() if $absent;
            import_initialdata($directory);
            $present->() if $present;
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

