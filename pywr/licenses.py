#!/usr/bin/env python

import calendar, datetime
import xml.etree.ElementTree as ET
from ._parameters import Parameter as BaseParameter
import numpy as np

inf = float('inf')

class License(BaseParameter):
    """Base license class from which others inherit

    This class should not be instantiated directly. Instead, use one of the
    subclasses (e.g. DailyLicense).
    """
    def __new__(cls, *args, **kwargs):
        if cls is License:
            raise TypeError('License cannot be instantiated directly')
        else:
            return BaseParameter.__new__(cls)

    def resource_state(self, timestep):
        raise NotImplementedError()


    @classmethod
    def from_xml(cls, xml):
        lic_type = xml.get('type')
        amount = float(xml.text)
        lic_types = {
            'annual': AnnualLicense,
            'daily': TimestepLicense,
            'timestep': TimestepLicense,
        }
        lic = lic_types[lic_type](amount)
        return lic

class TimestepLicense(License):
    """License limiting volume for a single timestep

    This is the simplest kind of license. The volume available each timestep
    is a fixed value. There is no resource state, as use today does not
    impact availability tomorrow.
    """
    def __init__(self, amount):
        """Initialise a new TimestepLicense

        Parameters
        ----------
        amount : float
            The maximum volume available in each timestep
        """
        self._amount = amount
    def value(self, timestep, scenario_indices=[0]):
        return self._amount
    def resource_state(self, timestep):
        return None

    def xml(self):
        xml = ET.Element('license')
        xml.set('type', 'timestep')
        xml.text = str(self._amount)
        return xml

# for now, assume a daily timestep
# in the future this will need to be more clever
class DailyLicense(TimestepLicense):
    pass

class StorageLicense(License):
    def __init__(self, amount):
        """A license with a volume to be spent over multiple timesteps

        This class should not be instantiated directly. Instead, use one of the
        subclasses such as AnnualLicense.

        Parameters
        ----------
        amount : float
            The volume of water available in each period
        """
        super(StorageLicense, self).__init__()
        self._amount = amount

    def setup(self, model):
        # Create a state array for the remaining licence volume.
        self._remaining = np.ones(len(model.scenarios.combinations))*self._amount

    def value(self, timestep, scenario_indices=[0]):
        i = self.node.model.scenarios.ravel_indices(scenario_indices)
        return self._remaining[i]

    def after(self, timestep):
        self._remaining -= self.node.flow*timestep.days
        self._remaining[self._remaining < 0] = 0.0

    def reset(self):
        self._remaining[...] = self._amount


class AnnualLicense(StorageLicense):
    """An annual license"""
    def __init__(self, amount):
        super(AnnualLicense, self).__init__(amount)
        # Record year ready to reset licence when the year changes.
        self._prev_year = None

    def value(self, timestep, scenario_indices=np.array([0], dtype=np.int32)):
        i = self.node.model.scenarios.ravel_indices(scenario_indices)
        timetuple = timestep.datetime.timetuple()
        day_of_year = timetuple.tm_yday
        days_in_year = 365 + int(calendar.isleap(timestep.datetime.year))
        if day_of_year == days_in_year:
            return self._remaining[i]
        else:
            return self._remaining[i] / (days_in_year - day_of_year + 1)

    def before(self, timestep):
        # Reset licence if year changes.
        if self._prev_year != timestep.datetime.year:
            self.reset()
            self._prev_year = timestep.datetime.year

    def xml(self):
        xml = ET.Element('license')
        xml.set('type', 'annual')
        xml.text = str(self._amount)
        return xml


class AnnualExponentialCostLicense(AnnualLicense):
    def __init__(self, amount, max_cost, k=1.0):
        super(AnnualExponentialCostLicense, self).__init__(amount)

        self._max_cost = max_cost
        self._k = k

    def value(self, timestep, scenario_indices=np.array([0], dtype=np.int32)):

        remaining = super(AnnualExponentialCostLicense, self).value(timestep, scenario_indices)
        expected = self._amount / (365 + int(calendar.isleap(timestep.datetime.year)))
        x = remaining / expected
        return self._max_cost * np.exp(-x/self._k)

class AnnualHyperbolaCostLicense(AnnualLicense):
    def __init__(self, amount, cost):
        super(AnnualHyperbolaCostLicense, self).__init__(amount)

        self._cost = cost

    def value(self, timestep, scenario_indices=np.array([0], dtype=np.int32)):

        remaining = super(AnnualHyperbolaCostLicense, self).value(timestep, scenario_indices)
        expected = self._amount / (365 + int(calendar.isleap(timestep.datetime.year)))
        x = remaining / expected
        try:
            return self._cost / x
        except ZeroDivisionError:
            return inf
