from   prettytable import PrettyTable

#--------------------------------------------
#--------------------------------------------
class AddrMap:
    """
    A class to manage register addresses ensuring unique register names and addresses.

    Attributes
    ----------
    registers : dict
        A dictionary to store register names and their corresponding addresses.

    Methods
    -------
    add(name, address):
        Adds a new register with a unique name and address.
    
    get(name):
        Retrieves the address of a given register name.
    
    rm(name):
        Removes a register by its name.
    
    display():
        Displays a table of all registers with their names and addresses.
    """

    def __init__(self):
        """
        Initializes the AddrMap class with an empty dictionary to store registers.
        """
        self.registers = {}

    def add(self, name, address):
        """
        Adds a new register with a unique name and address.

        Parameters
        ----------
        name : str
            The name of the register.
        address : str
            The address of the register.

        Raises
        ------
        ValueError
            If the register name or address already exists.
        """
        if name    in self.registers:
            raise ValueError(f"Name '{name}' already exists.")
        if address in self.registers.values():
            raise ValueError(f"Address '{address}' already exists.")
        self.registers[name] = address

    def get(self, name):
        """
        Retrieves the address of a given register name.

        Parameters
        ----------
        name : str
            The name of the register.

        Returns
        -------
        str or None
            The address of the register if found, otherwise None.
        """
        return self.registers.get(name, None)

    def rm(self, name):
        """
        Removes a register by its name.

        Parameters
        ----------
        name : str
            The name of the register to be removed.

        Raises
        ------
        ValueError
            If the register name does not exist.
        """
        if name in self.registers:
            del self.registers[name]
        else:
            raise ValueError(f"Name '{name}' does not exist.")

    def display(self):
        """
        Displays a table of all registers with their names and addresses.
        
        Returns
        -------
        None
            Prints a table of all registers with their names and addresses.
        """
        
        table = PrettyTable()
        
        table.field_names = ["Name", "Address"]
        
        for name, address in self.registers.items():
            table.add_row([address, name])
        
        print(table)
