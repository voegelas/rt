#$Header$

package RT::ScripScope;
use RT::Record;
@ISA= qw(RT::Record);

# {{{ sub new 
sub new  {
  my $proto = shift;
  my $class = ref($proto) || $proto;
  my $self  = {};
  bless ($self, $class);
  $self->{'table'} = "ScripScope";
  $self->_Init(@_);
  return ($self);
}
# }}}

# {{{ sub _Accessible 
sub _Accessible  {
  my $self = shift;
  my %Cols = ( Scrip  => 'read/write',
	    	Queue => 'read/write', 
	  	Template => 'read/write',
	     );
  return($self->SUPER::_Accessible(@_, %Cols));
}
# }}}

# {{{ sub Create 
sub Create  {
  my $self = shift;
  die "RT::Scrip->create stubbed\n";
  my $id = $self->SUPER::Create(Name => @_);
  $self->LoadById($id);
  
}
# }}}

# {{{ sub delete 
sub delete  {
  my $self = shift;
  my ($query_string,$update_clause);
  
  die ("ScripScope->Delete not implemented yet");
}
# }}}

# {{{ sub Load 
sub Load  {
  my $self = shift;
  
  my $identifier = shift;
  if (!$identifier) {
    return (undef);
  }	    

  if ($identifier !~ /\D/) {
    $self->SUPER::LoadById($identifier);
  }
  else {
    die "This code is never reached ;)";  
  }

  $self
  
 
}
# }}}

# {{{ sub ScripObj
sub ScripObj {
  my $self = shift;
  if (!$self->{'ScripObj'})  {
    require RT::Scrip;
    $self->{'ScripObj'} = RT::Scrip->new($self->CurrentUser);
    $self->{'ScripObj'}->Load($self->_Value('Scrip'), $self->_Value('Template'));
  }
  return ($self->{'ScripObj'});
}

# }}}
#
# ACCESS CONTROL
# 

# {{{ sub DESTROY
sub DESTROY {
    my $self = shift;
    $self->{'ScripObj'} = undef;
}
#}}}

1;


