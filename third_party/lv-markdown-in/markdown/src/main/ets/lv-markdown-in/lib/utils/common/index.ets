interface IMdRegister {
  HandleHyperlink: Function,
  HandleImage: Function
}

export let mdRegister: IMdRegister = {
  HandleHyperlink: (url: string) => {
    return true
  },
  HandleImage: (url: string) => {
    return true
  }
}