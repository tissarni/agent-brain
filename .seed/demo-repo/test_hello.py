import unittest

from hello import greet


class GreetTest(unittest.TestCase):
    def test_default_name(self):
        self.assertEqual(greet(), "Hello, world!")

    def test_given_name(self):
        self.assertEqual(greet("Ada"), "Hello, Ada!")


if __name__ == "__main__":
    unittest.main()
