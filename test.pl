my %STATUSTYPES = ( "nuke" => 1, "unnuke" => 2, "delpre" => 3, "undelpre" => 4);

# Convert Status (integer) to String (type)
# Params: (status)
# Return: Type (String)
sub statusToType {
  my $status = shift;
  my $type;
  my %rstatustypes = reverse %STATUSTYPES;
  $type = $rstatustypes{$status};
  return $type;
}

# Convert Status (integer) to String (type)
# Params: (status)
# Return: Type (String)
sub typeToStatus {
  my $type = shift;
  my $status;
  if(exists $STATUSTYPES{$type}){
    $status = $STATUSTYPES{$type};
  }
  return $status;
}

print typeToStatus("nuke");
