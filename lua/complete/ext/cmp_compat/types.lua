local cmp = {}

cmp.ConfirmBehavior = {
  Insert = 'insert',
  Replace = 'replace',
}

cmp.SelectBehavior = {
  Insert = 'insert',
  Select = 'select',
}

cmp.ContextReason = {
  Auto = 'auto',
  Manual = 'manual',
  TriggerOnly = 'triggerOnly',
  None = 'none',
}

cmp.TriggerEvent = {
  InsertEnter = 'InsertEnter',
  TextChanged = 'TextChanged',
}

cmp.PreselectMode = {
  Item = 'item',
  None = 'none',
}

cmp.ItemField = {
  Abbr = 'abbr',
  Kind = 'kind',
  Menu = 'menu',
}

return cmp
