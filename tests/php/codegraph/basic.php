<?php

class Exception {
}

interface I {
  const CST_IN_INTERFACE = 0;
}

function test_throw() {
  throw new Exception();
}

function test_instanceof() {
  if ($x instanceof Exception) {
  }
}

function test_interface_lookup() {
  echo I::CST_IN_INTERFACE;
}


class A {
  public $fld;
  function testThis() {
    echo $this->fld;
  }
}
