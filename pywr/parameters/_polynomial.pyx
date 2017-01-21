""" Module contains Polynomial Parameters """
from ._parameters import load_parameter
import numpy as np
cimport numpy as np


cdef class Polynomial1DParameter(Parameter):
    """ Parameter that returns the result of 1D polynomial evaluation

    The input to the polynomial can be either:
     - The previous flow of the attached node (default)
     - The previous flow of another `AbstractNode`
     - The current storage of an `AbstractStorage` node
     - The current value of another `Parameter`

    Parameters
    ----------
    coefficients : array like
        The 1 dimensional array of polynomial coefficients.
    node : `AbstractNode`
        An optional `AbstractNode` the flow of which is used to evaluate the polynomial.
    storage_node : `Storage`
        An optional `Storage` node the volume of which is used to evaluate the polynomial.
    parameter : iterable of Parameter objects or single Parameter
        An optional `Parameter` the value of which is used to evaluate the polynomial.
    use_proportional_volume : bool
        An optional boolean only used with a `Storage` node to switch between using absolute
         or proportional volume when evaluating the polynomial.
    """
    def __init__(self, coefficients, *args, **kwargs):
        self.coefficients = np.array(coefficients, dtype=np.float64)
        self._other_node = kwargs.pop('node', None)
        self._storage_node = kwargs.pop('storage_node', None)
        self._parameter = kwargs.pop('parameter', None)
        self.use_proportional_volume = kwargs.pop('use_proportional_volume', False)
        # Check only one of the above is given
        arg_check = [
            self._other_node is not None,
            self._storage_node is not None,
            self._parameter is not None,
        ]
        # Check we haven't been given an ambiguous number of objects
        if arg_check.count(True) > 1:
            raise ValueError('Only one of "node", "storage_node" or "parameter" keywords should be given.')
        super(Polynomial1DParameter, self).__init__(*args, **kwargs)

    cpdef double value(self, Timestep ts, ScenarioIndex scenario_index) except? -1:
        cdef int i
        cdef double x, y

        # Get the 'x' value to put in the polynomial
        if self._parameter is not None:
            x = self._parameter.value(ts, scenario_index)
        elif self._storage_node is not None:
            if self.use_proportional_volume:
                x = self._storage_node.current_pc[scenario_index._global_id]
            else:
                x = self._storage_node.volume[scenario_index._global_id]
        elif self._other_node is not None:
            x = self._other_node.flow[scenario_index._global_id]
        else:
            x = self._node.flow[scenario_index._global_id]

        y = 0.0
        for i in range(self.coefficients.shape[0]):
            y += self.coefficients[i]*x**i
        return y

    @classmethod
    def load(cls, model, data):
        node = None
        if 'node' in data:
            node = model._get_node_from_ref(model, data["node"])
        storage_node = None
        if 'storage_node' in data:
            storage_node = model._get_node_from_ref(model, data["storage_node"])
        parameter = None
        if 'parameter' in data:
            parameter = load_parameter(model, data["parameter"])

        coefficients = data.pop("coefficients")
        use_proportional_volume = data.pop("use_proportional_volume", False)
        parameter = cls(coefficients, node=node, storage_node=storage_node, parameter=parameter,
                        use_proportional_volume=use_proportional_volume)
        return parameter
Polynomial1DParameter.register()


cdef class Polynomial2DStorageParameter(Parameter):
    """ Parameter that returns the result of 2D polynomial evaluation

    The 2 dimensions of the polynomial are the volume of a `Storage` node and
    the current value of a `Parameter` respectively. Both must be given to this parameter.

    Parameters
    ----------
    coefficients : array like
        The 2 dimensional array of polynomial coefficients.
    storage_node : `Storage`
        A `Storage` node the volume of which is used to evaluate the polynomial.
    parameter : iterable of Parameter objects or single Parameter
        An `Parameter` the value of which is used to evaluate the polynomial.
    use_proportional_volume : bool
        An optional boolean only used with a `Storage` node to switch between using absolute
         or proportional volume when evaluating the polynomial.
    """
    def __init__(self, coefficients, storage_node, parameter, *args, **kwargs):
        self.coefficients = np.array(coefficients, dtype=np.float64)
        self._storage_node = storage_node
        self._parameter = parameter
        self.use_proportional_volume = kwargs.pop('use_proportional_volume', False)
        super(Polynomial2DStorageParameter, self).__init__(*args, **kwargs)

    cpdef double value(self, Timestep ts, ScenarioIndex scenario_index) except? -1:
        cdef int i, j
        cdef double x, y, z

        # Storage volume is 1st dimension
        if self.use_proportional_volume:
            x = self._storage_node.current_pc[scenario_index._global_id]
        else:
            x = self._storage_node.volume[scenario_index._global_id]
        # Parameter value is 2nd dimension
        y = self._parameter.value(ts, scenario_index)

        z = 0.0
        for i in range(self.coefficients.shape[0]):
            for j in range(self.coefficients.shape[1]):
                z += self.coefficients[i, j]*x**i*y**j
        return z

    @classmethod
    def load(cls, model, data):
        storage_node = model._get_node_from_ref(model, data["storage_node"])
        parameter = load_parameter(model, data["parameter"])
        coefficients = data.pop("coefficients")
        use_proportional_volume = data.pop("use_proportional_volume", False)
        parameter = cls(coefficients, storage_node, parameter, use_proportional_volume=use_proportional_volume)
        return parameter
Polynomial2DStorageParameter.register()