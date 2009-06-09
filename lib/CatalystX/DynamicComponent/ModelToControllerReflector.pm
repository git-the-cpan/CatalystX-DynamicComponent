package CatalystX::DynamicComponent::ModelToControllerReflector;
use Moose::Role;
use Moose::Util qw/does_role/;
use MooseX::Types::Moose qw/Str/;
use Moose::Util::TypeConstraints;
use namespace::autoclean;

my $mangle_attributes_on_generated_methods = sub {
    my ($meta, $config) = @_;
    foreach my $name (keys %{ $config->{methods}}) {
        my $m = $meta->get_method($name);
        $meta->register_method_attributes($m->body, ['Local']);
    }
};

with 'CatalystX::DynamicComponent' => {
    name => '_setup_dynamic_controller',
    pre_immutable_hook => $mangle_attributes_on_generated_methods,
};

requires 'setup_components';

after 'setup_components' => sub { shift->_setup_dynamic_controllers(@_); };

sub _setup_dynamic_controllers {
    my ($app) = @_;

    my @model_names = grep { /::Model::/ } keys %{ $app->components };
    foreach my $model_name (@model_names) {
        $app->_reflect_model_to_controller( $model_name, $app->components->{$model_name} );
    }
}

my $interface = 'CatalystX::DynamicComponent::ModelToControllerReflector::Strategy';
role_type $interface;

sub _reflect_model_to_controller {
    my ( $app, $model_name, $model ) = @_;

    # Model passed in as MyApp::Model::Foo, strip MyApp
    $model_name =~ s/^[^:]+:://;

    # Get Controller::Foo
    my $controller_name = $model_name;
    $controller_name =~ s/^Model::/Controller::/;

    # Get Foo
    my $suffix = $model_name;
    $suffix =~ s/Model:://;

    my %controller_methods;
    # FIXME - Abstract this strategy crap out.

    my $config = exists $app->config->{'CatalystX::DynamicComponent::ModelToControllerReflector'}
        ? $app->config->{'CatalystX::DynamicComponent::ModelToControllerReflector'} : {};
    my $strategy = exists $config->{reflection_strategy} ? $config->{reflection_strategy} : 'InterfaceRoles';
    $strategy = "CatalystX::DynamicComponent::ModelToControllerReflector::Strategy::$strategy";
    Class::MOP::load_class($strategy);
    $strategy->new;

    my $model_methods = $model->meta->get_method_map;
    foreach my $method_name ( $strategy->get_reflected_method_list($app, $model_name, $model) ) {
        # Note need to pass model name, as the method actually comes from
        # the underlying model class, not the Catalyst shim class we autogenerated.
        $controller_methods{$method_name} = 
             $app->generate_reflected_controller_action_method($suffix, $model_methods->{$method_name})
    }

    # Shallow copy so we don't stuff method refs in config
    my $controller_config = { %{$app->config->{$controller_name}||{}} };

    $controller_config->{methods} = \%controller_methods;
    $app->_setup_dynamic_controller( $controller_name, $controller_config );
}

sub generate_reflected_controller_action_method {
    my ( $app, $model, $method ) = @_;
    my $method_name = $method->name; # Is it worth passing the actual method object here?
    sub {
        my ($self, $c, @args) = @_;
        $c->res->header('X-From-Model', $model);
        my $response = $c->model($model)->$method_name( { name => $args[0] });
        $c->res->header('X-From-Model-Data', $response->{body});
        $c->res->body('OK');
        $c->stash->{response} = $response;
    };
}

1;

__END__

=head1 NAME

CatalystX::DynamicComponent::ModelToControllerReflector - Generate Catalyst controllers automaticall from models and configuration.

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 LINKS

L<Catalyst>, L<MooseX::MethodAttributes>, L<CatalystX::ModelsFromConfig>.

=head1 BUGS

Probably plenty, test suite certainly isn't comprehensive.. Patches welcome.

=head1 AUTHOR

Tomas Doran (t0m) <bobtfish@bobtfish.net>

=head1 LICENSE

This code is copyright (c) 2009 Tomas Doran. This code is licensed on the same terms as perl
itself.

=cut
